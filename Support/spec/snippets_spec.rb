require 'json'

# The snippets are property lists, read with macOS's own plutil,
# which is on every Mac TextMate runs on.
module SnippetFiles
  BUNDLE = File.expand_path('../..', __dir__)

  def self.all
    Dir[File.join(BUNDLE, 'Snippets', '*.tmSnippet')].sort.map do |path|
      json = IO.popen(['plutil', '-convert', 'json', '-o', '-', path], &:read)
      raise "#{path} is not a property list" unless $?.success?

      JSON.parse(json).merge('file' => File.basename(path))
    end
  end

  def self.inserting(pattern)
    all.select { |snippet| snippet['content'] =~ pattern }.map { |snippet| snippet['file'] }
  end

  # The should syntax, of rspec-expectations and of rspec-mocks,
  # is leaving this bundle for a bundle of its own,
  # and these snippets are held to that bundle's rules, not to these.
  def self.in_expect_syntax
    all.reject { |snippet| snippet['content'] =~ /\bshould|\.stub\(/ }
  end
end

# What a snippet inserts when every tab stop keeps its default:
# a placeholder becomes its default, a choice its first option,
# a mirror the value of the tab stop it mirrors,
# a transformation or variable a stand in name,
# and an empty tab stop the filler, nothing or what a person would type.
class SnippetExpansion
  require 'strscan'

  def initialize(content, filler:)
    @scanner = StringScanner.new(content)
    @filler  = filler
    @values  = {}
  end

  def to_s = expand(until_brace: false)

  # The words of every placeholder's default, which stand in for a person's own names.
  def placeholder_words
    to_s
    @values.values.join(' ').scan(/\w+[?!]?/)
  end

  private

  def expand(until_brace:)
    out = +''
    until @scanner.eos?
      if until_brace && @scanner.check(/\}/)
        @scanner.skip(/\}/)
        return out
      elsif @scanner.scan(/\\(.)/m)
        out << @scanner[1]
      elsif @scanner.scan(/\$\{(\w+)\|/)
        name = @scanner[1]
        out << (@values[name] = @scanner.scan(/[^,|]*/))
        @scanner.skip(/[^|]*\|\}/)
      elsif @scanner.scan(/\$\{(\w+):-?/)
        name = @scanner[1]
        out << (@values[name] = expand(until_brace: true))
      elsif @scanner.scan(/\$\{\w+\/(?:\\.|[^\\\/])*\/(?:\\.|[^\\\/])*\/\w*\}/)
        out << 'Subject'
      elsif @scanner.scan(/\$\{(\d+)\}|\$(\d+)/)
        out << @values.fetch(@scanner[1] || @scanner[2], @filler)
      elsif @scanner.scan(/\$\{([A-Z_]+)\}|\$([A-Z_]+)/)
        out << 'Subject'
      else
        out << @scanner.getch
      end
    end
    out
  end
end

RSpec.describe 'The snippets' do
  it 'are each a property list with content, a name, a scope and a uuid' do
    incomplete = SnippetFiles.all.reject do |snippet|
      %w[content name scope uuid].all? { |key| snippet.key?(key) }
    end

    expect(incomplete).to eq([])
  end

  it 'each have their own tab trigger' do
    triggers = SnippetFiles.in_expect_syntax.map { |snippet| snippet['tabTrigger'] }.compact
    shared = triggers.tally.select { |_, count| count > 1 }.keys

    expect(shared).to eq([])
  end

  it 'insert Ruby that parses, with every tab stop at its default' do
    require 'prism'

    # An empty tab stop is either left empty, as in instance_double(Object)$0,
    # or where a person has to type something, as in config.$0.
    unparsed = SnippetFiles.in_expect_syntax.reject do |snippet|
      ['', 'filled_in'].any? do |filler|
        ruby = SnippetExpansion.new(snippet['content'], filler:).to_s
        # A chained modifier, like .and, needs something to chain to.
        ruby = "subject#{ruby}" if ruby.start_with?('.')
        Prism.parse(ruby).success?
      end
    end

    expect(unparsed.map { |snippet| snippet['file'] }).to eq([])
  end

  it 'insert only names an RSpec example or example group defines' do
    require 'prism'

    # Names RSpec answers through method_missing or a library this suite does not load.
    # Loading rspec-rails takes a Rails application,
    # so its names were checked against the rspec-rails 8.0.4 source instead.
    predicates = %w[be_predicate have_predicate]
    capybara   = %w[background feature given given! save_and_open_page scenario]
    rspec_rails = %w[
      at be_a_new be_new_record be_routable be_valid driven_by
      have_been_enqueued have_been_performed have_broadcasted_to have_enqueued_job
      have_enqueued_mail have_http_status have_performed_job have_stream_for
      have_stream_from on_queue receive_inbound_email redirect_to render_template
      route_to send_email
    ]
    elsewhere = predicates + capybara + rspec_rails

    undefined = SnippetFiles.in_expect_syntax.flat_map do |snippet|
      expansion = SnippetExpansion.new(snippet['content'], filler: '')
      ruby = expansion.to_s
      ruby = "subject#{ruby}" if ruby.start_with?('.')
      calls = []
      queue = [Prism.parse(ruby).value]
      until queue.empty?
        node = queue.shift
        calls << node.name.to_s if node.is_a?(Prism::CallNode) && node.receiver.nil?
        queue.concat(node.compact_child_nodes)
      end

      calls.reject do |name|
        expansion.placeholder_words.include?(name) ||
          elsewhere.include?(name) ||
          # Asking respond_to? would let any be_ or have_ name through,
          # since RSpec turns those into predicate matchers at run time.
          self.class.method_defined?(name) ||
          self.class.private_method_defined?(name) ||
          self.class.respond_to?(name) ||
          # Modifiers, like and_return or once, chain onto a message expectation.
          RSpec::Mocks::MessageExpectation.method_defined?(name)
      end.map { |name| "#{snippet['file']}: #{name}" }
    end

    expect(undefined).to eq([])
  end

  it 'require the helpers by name, as RSpec puts spec on the load path' do
    expect(SnippetFiles.inserting(/File\.dirname\(__FILE__\)/)).to eq([])
  end

  describe 'insert nothing RSpec 3 removed' do
    it 'such as any_number_of_times, which allow replaces' do
      expect(SnippetFiles.inserting(/\bany_number_of_times\b/)).to eq([])
    end

    it 'such as mock, which double replaces' do
      expect(SnippetFiles.inserting(/(?<![.\w])mock\(/)).to eq([])
    end

    it 'such as RSpec::Runner, which RSpec.configure replaces' do
      expect(SnippetFiles.inserting(/\bRSpec::Runner\b/)).to eq([])
    end

    it 'such as controller_name, from RSpec 1' do
      expect(SnippetFiles.inserting(/\bcontroller_name\b/)).to eq([])
    end

    it 'such as mock_model, which moved to the rspec-activemodel-mocks gem' do
      expect(SnippetFiles.inserting(/\bmock_model\b/)).to eq([])
    end
  end
end
