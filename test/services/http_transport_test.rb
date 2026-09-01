require "test_helper"

class HttpTransportTest < ActiveSupport::TestCase
  def transport
    HttpTransport.new
  end

  test "ssl_options disables TLS for plain http but still sets timeouts" do
    # Timeouts used to be nested inside the https-only branch, so a plain
    # http:// endpoint (the default TRINO_URL is one) fell back to Net::HTTP's
    # own default read/open timeout instead of failing fast.
    assert_equal({ open_timeout: 10, read_timeout: 60, use_ssl: false },
                 transport.send(:ssl_options, URI("http://polaris:8181")))
  end

  test "ssl_options enables TLS for https without a CA file" do
    ca_file = ENV["INTERNAL_CA_FILE"]
    ENV["INTERNAL_CA_FILE"] = nil

    assert_equal({ use_ssl: true, open_timeout: 10, read_timeout: 60 },
                 transport.send(:ssl_options, URI("https://polaris:8181")))
  ensure
    ENV["INTERNAL_CA_FILE"] = ca_file
  end

  test "ssl_options points at the internal CA when present" do
    ca_file = Tempfile.new("ca.pem")
    old = ENV["INTERNAL_CA_FILE"]
    ENV["INTERNAL_CA_FILE"] = ca_file.path

    options = transport.send(:ssl_options, URI("https://polaris:8181"))
    assert_equal ca_file.path, options[:ca_file]
  ensure
    ENV["INTERNAL_CA_FILE"] = old
    ca_file&.close!
  end

  test "ssl_options ignores a CA path that does not exist" do
    old = ENV["INTERNAL_CA_FILE"]
    ENV["INTERNAL_CA_FILE"] = "/nonexistent/ca.pem"

    options = transport.send(:ssl_options, URI("https://polaris:8181"))
    assert_nil options[:ca_file]
  ensure
    ENV["INTERNAL_CA_FILE"] = old
  end

  test "ApiError surfaces the server's error.message from a JSON body" do
    error = HttpTransport::ApiError.new(
      500,
      '{"error":{"message":"No default-warehouse configured","type":"IllegalStateException","code":500}}'
    )

    assert_equal "HTTP 500 — No default-warehouse configured", error.message
    assert_equal 500, error.status
  end

  test "ApiError stays bare when the body is not JSON" do
    error = HttpTransport::ApiError.new(502, "Bad Gateway")

    assert_equal "HTTP 502", error.message
  end

  test "ApiError stays bare when the body carries no message" do
    error = HttpTransport::ApiError.new(404, '{"error":{"code":404}}')

    assert_equal "HTTP 404", error.message
  end
end
