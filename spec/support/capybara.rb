require "capybara/rails"
require "capybara/minitest"

Capybara.register_driver :headless_chrome do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument("--headless=new")
  options.add_argument("--no-sandbox")
  options.add_argument("--disable-gpu")
  options.add_argument("--disable-dev-shm-usage")

  chrome_path = ENV["CHROME_BIN"] ||
    Dir.glob(File.join(Dir.home, ".cache/puppeteer/chrome/linux-*/chrome-linux64/chrome")).first
  options.binary = chrome_path if chrome_path

  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

RSpec.configure do |config|
  config.include Capybara::DSL, type: :system
  config.include Capybara::Minitest::Assertions, type: :system

  config.before(:each, type: :system) do
    driven_by :headless_chrome
    Capybara.server_port = 30_01 + ENV["TEST_ENV_NUMBER"].to_i
  end
end
