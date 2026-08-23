namespace :docs do
  COUNTER_SCRIPT = -> {
    data_id = ENV.fetch("DATA_TRACKING")
    %(    <script src="https://cdn.counter.dev/script.js" data-id="#{data_id}" data-utcoffset="2"></script>)
  }

  desc "Generate RDoc documentation"
  task :build do
    sh "bundle exec rdoc --markup markdown --output doc --readme README.md app lib config Gemfile Rakefile --exclude config/credentials.yml.enc"
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
        content.sub!("<body", "  #{COUNTER_SCRIPT.call}\n<body")
        File.write(file, content)
        count += 1
      end
    end
    puts "Injected counter.dev script into #{count} HTML files."
  end
end
