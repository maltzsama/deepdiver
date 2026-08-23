require "rails_helper"

RSpec.describe ApplicationHelper, "#pager_nav", type: :helper do
  let(:pagy) { Pagy.new(count: 5000, page: 50, limit: 50) }

  it "renders styled pages with gap and active page badge" do
    html = helper.pager_nav(pagy)

    expect(html).to include("pager-gap")
    expect(html).to include('aria-current="page"')
    expect(html).to include("badge-ok")
    expect(html).not_to include("pager-disabled")
    # URLs preserve query params and the current page renders as active badge
    expect(html).to include("page=49")
    expect(html).to include(">50</span>")
  end

  it "dims the previous arrow on the first page" do
    html = helper.pager_nav(Pagy.new(count: 5000, page: 1, limit: 50))

    expect(html).to include("pager-disabled")
  end

  it "returns nil for a single page" do
    expect(helper.pager_nav(Pagy.new(count: 10, limit: 50))).to be_nil
  end
end
