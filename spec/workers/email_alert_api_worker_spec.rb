require "rails_helper"

RSpec.describe EmailAlertApiWorker do
  include GdsApi::TestHelpers::EmailAlertApi

  before do
    email_alert_api_accepts_alert
  end

  around do |example|
    Sidekiq::Testing.fake! { example.run }
  end

  it "asynchronously sends a notification to email alert api" do
    described_class.perform_async(some: "payload")

    expect(described_class.jobs.size).to eq(1)
    described_class.drain
    expect(described_class.jobs.size).to eq(0)

    assert_email_alert_sent("some" => "payload")
  end
end
