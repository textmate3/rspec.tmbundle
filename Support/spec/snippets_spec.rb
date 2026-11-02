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
end

RSpec.describe 'The snippets' do
  it 'are each a property list with content, a name, a scope and a uuid' do
    incomplete = SnippetFiles.all.reject do |snippet|
      %w[content name scope uuid].all? { |key| snippet.key?(key) }
    end

    expect(incomplete).to eq([])
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
  end
end
