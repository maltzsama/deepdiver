namespace :docs do
  COUNTER_SCRIPT = <<~HTML.chomp
    <script src="https://cdn.counter.dev/script.js" data-id="2a2c5d2b-5c34-4212-be47-a2e658d11dbf" data-utcoffset="2"></script>
  HTML

  desc "Generate RDoc documentation"
  task :build do
    sh "bundle exec rdoc --markup markdown --output doc --readme README.md app lib config Gemfile Rakefile"
    Rake::Task["docs:inject_counter"].invoke
  end

  desc "Inject counter.dev tracking script into all generated HTML files"
  task :inject_counter do
    require "fileutils"
    count = 0
    Dir["doc/**/*.html"].each do |file|
      content = File.read(file)
      next if content.include?("cdn.counter.dev")

      if content.include?("<body")
        content.sub!("<body", "  #{COUNTER_SCRIPT}\n<body")
        File.write(file, content)
        count += 1
      end
    end
    puts "Injected counter.dev script into #{count} HTML files."
  end
end
