module PublishingApiHelpers
  def write_payload(document)
    copy = FactoryGirl.create(document["document_type"], document)
    copy.delete("last_edited_at")
    copy.delete("publication_state")
    copy.delete("first_published_at")
    copy.delete("public_updated_at")
    copy.delete("state_history")
    copy
  end

  def assert_no_publishing_api_put_content(content_id)
    assert_publishing_api_put_content(content_id, nil, 0)
  end
end

RSpec.configuration.include PublishingApiHelpers
