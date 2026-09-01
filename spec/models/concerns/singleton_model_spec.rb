require "rails_helper"

RSpec.describe SingletonModel do
  it "returns the same singleton row on repeated access" do
    first = AlertSetting.instance
    second = AlertSetting.instance

    expect(second).to eq(first)
    expect(AlertSetting.count).to eq(1)
  end

  it "rescues a bootstrap race and returns the winner's row" do
    allow(AlertSetting).to receive(:first_or_create!).and_raise(ActiveRecord::RecordNotUnique)
    existing = create(:alert_setting)

    expect(AlertSetting.instance).to eq(existing)
  end
end