require 'rails_helper'

RSpec.describe Manual do
  context "#save" do
    def manual_content_item
      {
        "base_path" => "/guidance/a-manual",
        "content_id" => "b1dc075f-d946-4bcb-a5eb-941f8c8188cf",
        "description" => "A manual description",
        "details" => {
          "body" => "A manual body",
          "child_section_groups" => [
            {
              "title" => "Contents",
              "child_sections" => [
                {
                  "title" => "First section",
                  "description" => "This is a manual's first section",
                  "base_path" => "/guidance/a-manual/first-section"
                },
                {
                  "title" => "Second section",
                  "description" => "This is a manual's second section",
                  "base_path" => "/guidance/a-manual/second-section"
                },
              ]
            }
          ],
          "change_notes" => [
            {
              "base_path" => "/guidance/a-manual/first-section",
              "title" => "First section",
              "change_note" => "New section added.",
              "published_at" => "2015-12-23T14:38:51+00:00"
            },
            {
              "base_path" => "/guidance/a-manual/second-section",
              "title" => "Second section",
              "change_note" => "New section added.",
              "published_at" => "2015-12-23T14:38:51+00:00"
            },
          ]
        },
        "document_type" => "manual",
        "schema_name" => "manual",
        "locale" => "en",
        "public_updated_at" => "2016-02-02T12:28:41.000Z",
        "publishing_app" => "specialist-publisher",
        "redirects" => [],
        "rendering_app" => "manuals-frontend",
        "routes" => [
          {
            "path" => "/guidance/a-manual",
            "type" => "exact"
          },
          {
            "path" => "/guidance/a-manual/updates",
            "type" => "exact"
          }
        ],
        "title" => "A Manual",
        "analytics_identifier" => nil,
        "phase" => "live",
        "update_type" => "major",
        "need_ids" => [],
        "publication_state" => "live",
        "live_version" => 2,
        "version" => 2
      }
    end

    let(:test_content_id) { SecureRandom.uuid }
    let(:organisations_content_id) { SecureRandom.uuid }
    let(:current_user) { double(User, organisations_content_id: organisations_content_id) }

    before do
      publishing_api_has_content([manual_content_item], document_type: "manual", fields: [:content_id])
      stub_publishing_api_put_content(test_content_id, {})
      stub_publishing_api_patch_links(test_content_id, {})
    end

    it "should put content to publishing-api" do
      test_path = "test/base_path"

      test_params = {
        base_path: test_path,
        content_id: test_content_id,
        title: "title",
        summary: "summary",
        body: "body"
      }

      expected_params = {
        base_path: test_path,
        content_id: test_content_id,
        title: "title",
        description: "summary",
        details: {
          body: "body",
          child_section_groups: [],
          change_notes: [],
        },
        routes: [
          {
            path: test_path,
            type: "exact"
          }
        ]
      }

      manual = Manual.new(test_params)
      manual.base_path = test_path
      manual.organisation_content_ids = [organisations_content_id]

      expected_links_params = {
        links: {
        organisations: manual.organisation_content_ids
        }
      }

      expect(manual.save).to eq(true)

      assert_publishing_api_put_content(manual.content_id, request_json_includes(expected_params))
      assert_publishing_api_patch_links(manual.content_id, request_json_includes(expected_links_params))
    end
  end

  it "should have max number per page set" do
    expect(Manual.max_numbers_of_manuals).to eq(10)
  end
end
