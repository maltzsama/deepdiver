require "rails_helper"

RSpec.describe "Content-Security-Policy", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it "reports violations without enforcing the policy" do
    get root_path

    expect(response.headers["Content-Security-Policy-Report-Only"]).to be_present
    expect(response.headers["Content-Security-Policy"]).to be_nil
  end

  it "sets the key directives" do
    get root_path

    header = response.headers["Content-Security-Policy-Report-Only"]

    expect(header).to include("default-src 'self'")
    expect(header).to include("object-src 'none'")
    expect(header).to include("frame-ancestors 'none'")
    expect(header).to include("script-src 'self'")
    # importmap-rails tags its inline module preload script with the request
    # nonce so it is not itself a violation once the policy enforces.
    expect(header).to match(/script-src 'self' 'nonce-/)
  end
end
