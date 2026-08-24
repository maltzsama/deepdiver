namespace :docs do
  # counter.dev is a privacy-friendly hit counter. The id is not a credential in
  # the usual sense (it ships in the page), but it identifies the account, so it
  # comes from the DATA_TRACKING secret rather than living in the repo.
  COUNTER_SCRIPT = lambda do
    data_id = ENV["DATA_TRACKING"].to_s.strip
    return nil if data_id.empty?

    %(<script src="https://cdn.counter.dev/script.js" data-id="#{data_id}" data-utcoffset="2"></script>)
  end

  # RDoc renders whatever --main points at as the landing page. Without it the
  # index falls back to "This is the API documentation for RDoc Documentation".
  # The file also has to be in the source list or there is no page to point at.
  MAIN_PAGE = "README.md".freeze

  # Everything RDoc should read. app/assets/builds holds compiled Tailwind CSS,
  # which is megabytes of generated output with nothing to document.
  # `docs` is included so the guides the README links to (security, the Helm
  # remediation notes) become pages instead of dead links on the published site.
  SOURCES = %w[README.md docs app lib config Gemfile Rakefile].freeze
  EXCLUDES = %w[
    config/credentials.yml.enc
    app/assets/builds
  ].freeze

  desc "Generate RDoc documentation"
  task :build do
    excludes = EXCLUDES.map { |path| "--exclude #{path}" }.join(" ")
    sh "bundle exec rdoc --markup markdown --output doc " \
       "--main #{MAIN_PAGE} --title 'LakeDeepDiver' " \
       "#{excludes} #{SOURCES.join(' ')}"
    Rake::Task["docs:inject_counter"].invoke
  end

  # Marks our own injection. Detecting "cdn.counter.dev" instead would also
  # match this very file rendered as documentation, which made the task report
  # pages as already tracked when they were not.
  MARKER = "<!-- counter.dev -->".freeze

  desc "Inject counter.dev tracking script into all generated HTML files"
  task :inject_counter do
    script = COUNTER_SCRIPT.call

    if script.nil?
      warn "docs:inject_counter: DATA_TRACKING is unset; skipping tracking injection."
      next
    end

    files = Dir["doc/**/*.html"]
    raise "docs:inject_counter: no HTML files under doc/ - run docs:build first" if files.empty?

    injected = 0
    skipped = 0
    missed = []

    files.each do |file|
      content = File.read(file)

      if content.include?(MARKER)
        skipped += 1
        next
      end

      # Right after the <body> open tag. RDoc emits HTML5 without a closing
      # </head>, and the previous version injected before "<body", which put
      # the script between head and body - a spot browsers have to relocate.
      updated = content.sub(/(<body\b[^>]*>)/i) { "#{Regexp.last_match(1)}\n#{MARKER}\n#{script}" }

      if updated == content
        missed << file
        next
      end

      File.write(file, updated)
      injected += 1
    end

    puts "docs:inject_counter: injected into #{injected} file(s), #{skipped} already tracked."

    # A silent no-op means the published docs lose tracking with no signal.
    raise "docs:inject_counter: no <body> found in #{missed.size} file(s): #{missed.first(5).join(', ')}" if missed.any?
  end

  desc "Verify the generated docs: README landing page and tracking script present"
  task :verify do
    index = "doc/index.html"
    raise "docs:verify: #{index} missing - run docs:build" unless File.exist?(index)

    content = File.read(index)

    if content.include?("This is the API documentation for")
      raise "docs:verify: index.html still shows RDoc's placeholder page; --main did not take effect"
    end

    if ENV["DATA_TRACKING"].to_s.strip.empty?
      warn "docs:verify: DATA_TRACKING unset; skipping the tracking assertion."
    elsif !content.include?("cdn.counter.dev")
      raise "docs:verify: tracking script missing from #{index}"
    end

    puts "docs:verify: ok"
  end
end
