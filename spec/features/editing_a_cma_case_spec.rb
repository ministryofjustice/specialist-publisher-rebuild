require 'spec_helper'

RSpec.feature "Editing a CMA case", type: :feature do
  let(:cma_case) {
    FactoryGirl.create(:cma_case, title: "Example CMA Case", state_history: { "1" => "draft" })
  }
  let(:content_id) { cma_case['content_id'] }
  let(:save_button_disable_with_message) { page.find_button('Save as draft')["data-disable-with"] }

  before do
    Timecop.freeze(Time.parse("2015-12-03T16:59:13+00:00"))
    log_in_as_editor(:cma_editor)

    stub_any_publishing_api_put_content
    stub_any_publishing_api_patch_links

    publishing_api_has_content([cma_case], hash_including(document_type: CmaCase.document_type))
    publishing_api_has_item(cma_case)

    visit "/cma-cases/#{content_id}"
    click_link "Edit document"
  end

  after do
    Timecop.return
  end

  scenario "successful update of a draft" do
    updated_cma_case = cma_case.deep_merge(
      "title" => "Changed title",
      "description" => "Changed summary",
      "base_path" => "/cma-cases/changed-title",
      "routes" => [{ "path" => "/cma-cases/changed-title", "type" => "exact" }],
      "details" => {
        "metadata" => {
          "opened_date" => "2014-01-01",
          "market_sector" => ["energy"],
        },
        "body" => [
          {
            "content_type" => "text/govspeak",
            "content" => "## Header" + ("\r\n\r\nThis is the long body of an example CMA case" * 2)
          },
          {
            "content_type" => "text/html",
            "content" => ("<h2 id=\"header\">Header</h2>\n" + "\n<p>This is the long body of an example CMA case</p>\n" * 2)
          }
        ],
        "headers" => [{
          "text" => "Header",
          "level" => 2,
          "id" => "header",
        }],
      }
    )
    expected_sent_payload = write_payload(updated_cma_case)

    fill_in "Title", with: "Changed title"
    fill_in "Summary", with: "Changed summary"
    fill_in "Body", with: "## Header" + ("\n\nThis is the long body of an example CMA case" * 2)
    fill_in "Opened date", with: "2014-01-01"
    select "Energy", from: "Market sector"

    expect(page).to have_css('div.govspeak-help')
    expect(page).to have_content('Add attachment')
    expect(save_button_disable_with_message).to eq("Saving...")

    click_button "Save as draft"

    assert_publishing_api_put_content(content_id, expected_sent_payload)

    expect(page.status_code).to eq(200)
    expect(page).to have_content("Updated Changed title")
  end

  context "a published case" do
    let(:cma_case) {
      FactoryGirl.create(:cma_case,
        :published,
        title: "Example CMA Case",
        description: "Summary with a typox",
        state_history: { "1" => "draft", "2" => "published" },
        details: {
          "body" => [
            { "content_type" => "text/govspeak", "content" => "A body" },
            { "content_type" => "text/html", "content" => "<p>A body</p>\n" },
          ],
          "metadata" => {
            "bulk_published" => true,
          }
        }).tap { |payload| payload["details"].delete("headers") }
    }

    scenario "a major update adds to the change history" do
      fill_in "Title", with: "Changed title"

      choose "Update type major"
      fill_in "Change note", with: "This is a change note."
      click_button "Save as draft"

      expected_change_history = cma_case['details']['change_history'] + [
        {
          "public_timestamp" => Time.current.iso8601,
          "note" => "This is a change note.",
        }
      ]

      changed_json = {
        "title" => "Changed title",
        "update_type" => "major",
        "details" => cma_case["details"].merge("change_history" => expected_change_history),
      }
      assert_publishing_api_put_content(content_id, request_json_includes(changed_json))
    end

    scenario "a minor update doesn't add to the change history" do
      fill_in "Summary", with: "Summary without a typo"

      choose "Update type minor"
      click_button "Save as draft"

      changed_json = {
        "description" => "Summary without a typo",
        "update_type" => "minor",
        "details" => cma_case["details"],
      }
      assert_publishing_api_put_content(content_id, request_json_includes(changed_json))
    end

    context "when a document already has a change note" do
      let(:cma_case) do
        FactoryGirl.create(
          :cma_case,
          update_type: "major",
          first_published_at: "2016-01-01",
          details: {
            change_history: [
              {
                "public_timestamp" => "2016-01-01T00:00:00+00:00",
                "note" => "First published."
              },
              {
                "public_timestamp" => "2016-02-02T00:00:00+00:00",
                "note" => "Some change note"
              },
            ]
          }
        )
      end

      it "updates the timestamp on the existing change note" do
        radio_major = field_labeled("cma_case_update_type_major")
        expect(radio_major).to be_checked

        expect(page).to have_content("Some change note")

        click_button "Save as draft"

        assert_publishing_api_put_content(content_id, ->(request) {
          payload = JSON.parse(request.body)
          change_history = payload.fetch("details").fetch("change_history")

          expect(change_history).to eq [
            { "public_timestamp" => "2016-01-01T00:00:00+00:00", "note" => "First published." },
            { "public_timestamp" => "2015-12-03T16:59:13+00:00", "note" => "Some change note" }
          ]
        })
      end
    end

    context "when the document has a temporary update type" do
      let(:cma_case) do
        FactoryGirl.create(
          :cma_case,
          update_type: "minor",
          first_published_at: "2016-01-01",
          details: {
            temporary_update_type: true,
            change_history: [
              {
                "public_timestamp" => "2015-01-01T00:00:00+00:00",
                "note" => "First published."
              },
              {
                "public_timestamp" => "2015-02-02T00:00:00+00:00",
                "note" => "Some change note"
              },
            ]
          }
        )
      end

      it "appends to the change history, rather than updating the last item" do
        radio_minor = field_labeled("cma_case_update_type_minor")
        radio_major = field_labeled("cma_case_update_type_major")

        expect(radio_minor).not_to be_checked
        expect(radio_major).not_to be_checked

        choose "Update type major"
        fill_in "Change note", with: "New change note"

        click_button "Save as draft"

        assert_publishing_api_put_content(content_id, ->(request) {
          payload = JSON.parse(request.body)
          change_history = payload.fetch("details").fetch("change_history")

          expect(change_history).to eq [
            { "public_timestamp" => "2015-01-01T00:00:00+00:00", "note" => "First published." },
            { "public_timestamp" => "2015-02-02T00:00:00+00:00", "note" => "Some change note" },
            { "public_timestamp" => "2015-12-03T16:59:13+00:00", "note" => "New change note" }
          ]
        })
      end
    end

    context "a bulk published document" do
      scenario "the 'bulk published' flag isn't lost after an update" do
        expect(cma_case["details"]["metadata"]["bulk_published"]).to be_truthy
        fill_in "Summary", with: "An updated summary"

        choose "Update type minor"
        click_button "Save as draft"

        changed_json = {
          "description" => "An updated summary",
          "update_type" => "minor",
          "details" => cma_case["details"], # bulk_published is still true in the metadata
        }
        assert_publishing_api_put_content(content_id, request_json_includes(changed_json))
        expect(page).to have_content('Bulk published true')
      end
    end
  end

  scenario "attempted update of a draft with invalid data" do
    fill_in "Title", with: "Changed title"
    fill_in "Summary", with: "Changed summary"
    fill_in "Body", with: "<script>alert('hello')</script>"
    fill_in "Opened date", with: "Not a date"
    select "Energy", from: "Market sector"

    click_button "Save as draft"

    expect(page).to have_css('.elements-error-summary')
    expect(page).to have_css('.elements-error-message')

    expect(page).to have_content("Opened date should be formatted YYYY-MM-DD")
    expect(page).to have_content("Body cannot include invalid Govspeak")
    expect(page).to have_content("Please fix the following errors")

    expect(page.status_code).to eq(422)
  end

  context "with attachments" do
    let(:asset_manager_response) {
      {
        id: 'http://asset-manager.dev.gov.uk/assets/another_image_id',
        file_url: "http://assets-origin.dev.gov.uk/media/56c45553759b740609000000/cma_case_image.jpg",
      }
    }
    let(:existing_attachments) {
      [
        {
          "content_id" => "77f2d40e-3853-451f-9ca3-a747e8402e34",
          "url" => "https://assets.digital.cabinet-office.gov.uk/media/513a0efbed915d425e000002/asylum-support-image.jpg",
          "content_type" => "application/jpeg",
          "title" => "asylum report image title",
          "created_at" => "2015-12-03T16:59:13+00:00",
          "updated_at" => "2015-12-03T16:59:13+00:00"
        },
        {
          "content_id" => "ec3f6901-4156-4720-b4e5-f04c0b152141",
          "url" => "https://assets.digital.cabinet-office.gov.uk/media/513a0efbed915d425e000002/asylum-support-pdf.pdf",
          "content_type" => "application/pdf",
          "title" => "asylum report pdf title",
          "created_at" => "2015-12-03T16:59:13+00:00",
          "updated_at" => "2015-12-03T16:59:13+00:00"
        }
      ]
    }

    before do
      stub_request(:post, "#{Plek.find('asset-manager')}/assets")
        .with(body: %r{.*})
        .to_return(body: asset_manager_response.to_json, status: 201)
    end

    %i(draft published).each do |publication_state|
      let(:cma_case) {
        FactoryGirl.create(
          :cma_case,
          publication_state,
          title: "Example CMA Case",
          details: { "attachments" => existing_attachments }
        )
      }

      #TODO this test isn't actually checking that the attachment has been added
      scenario "adding an attachment to a #{publication_state} CMA case" do
        updated_cma_case = cma_case.deep_merge(
          "update_type" => "minor",
          "details" => {
            "body" => [
              {
                "content_type" => "text/govspeak",
                "content" => "[InlineAttachment:asylum-support-image.jpg]"
              },
              {
                "content_type" => "text/html",
                "content" => "<p><a href=\"https://assets.digital.cabinet-office.gov.uk/media/513a0efbed915d425e000002/asylum-support-image.jpg\">asylum report image title</a></p>\n"
              }
            ],
          },
        )

        expect(page).not_to have_link("Delete", href: "/")
        click_link "Add attachment"
        expect(page.status_code).to eq(200)

        expect(page).to have_link("Your documents", href: "/cma-cases")
        fill_in "Title", with: "New cma case image"
        page.attach_file('attachment_file', "spec/support/images/cma_case_image.jpg")

        click_button "Save attachment"

        expect(page.status_code).to eq(200)
        expect(page).to have_content("Editing Example CMA Case")
        expect(page).to have_content("New cma case image")
        expect(page).to have_content("[InlineAttachment:asylum-support-image.jpg]")

        fill_in "Body", with: "[InlineAttachment:asylum-support-image.jpg]"
        choose "Update type minor"

        publishing_api_has_item(updated_cma_case)

        click_button "Save as draft"

        assert_publishing_api_put_content(content_id, write_payload(updated_cma_case))

        expect(page).to have_content("[InlineAttachment:asylum-support-image.jpg]")
      end

      scenario "editing an attachment on a #{publication_state} CMA case" do
        # this is to force app to not update asset manager on only-name edits
        stub_request(:post, "#{Plek.find('asset-manager')}/assets")
          .with(body: %r{.*})
          .to_return(body: asset_manager_response.to_json, status: 500)

        expect(page).to have_button("Delete")
        find('.attachments').first(:link, "edit").click
        expect(page.status_code).to eq(200)
        expect(find('#attachment_title').value).to eq('asylum report image title')

        fill_in "Title", with: "Updated cma case image"

        click_button("Save attachment")

        expect(page.status_code).to eq(200)
        expect(page).to have_content("Editing Example CMA Case")
      end

      context "when the document is in an invalid state" do
        let(:cma_case) { FactoryGirl.create(:cma_case, details: { body: "" }) }

        scenario "successfully adding an attachment to the invalid document" do
          click_link "Add attachment"

          fill_in "Title", with: "Some title"
          page.attach_file('attachment_file', "spec/support/images/cma_case_image.jpg")
          click_button "Save attachment"

          expect(page.status_code).to eq(200)
          expect(page).to have_content("Editing Example document")
        end
      end

      scenario "adding a nil attachment on a #{publication_state} CMA case" do
        # this is to force app to not update asset manager on invalid error
        stub_request(:post, "#{Plek.find('asset-manager')}/assets")
          .to_return(body: asset_manager_response.to_json, status: 500)

        click_link "Add attachment"
        expect(page.status_code).to eq(200)

        fill_in "Title", with: "Updated cma case image"

        click_button("Save attachment")

        expect(page.status_code).to eq(200)
        expect(page).to have_content("Adding an attachment failed. Please make sure you have uploaded an attachment")
      end


      scenario "editing an attachment on a #{publication_state} CMA case" do
        stub_request(:put, %r{#{Plek.find('asset-manager')}/assets/.*})
          .to_return(body: asset_manager_response.to_json, status: 201)
        find('.attachments').first(:link, "edit").click
        expect(page.status_code).to eq(200)
        expect(find('#attachment_title').value).to eq('asylum report image title')

        expect(page).to have_content('asylum-support-image.jpg')
        fill_in "Title", with: "Updated cma case image"
        page.attach_file('attachment_file', "spec/support/images/updated_cma_case_image.jpg")

        click_button("Save attachment")

        expect(page.status_code).to eq(200)
        expect(page).to have_content("Editing Example CMA Case")
      end

      scenario "deleting an attachment on a CMA case" do
        stub_request(:delete, %r{#{Plek.find('asset-manager')}/assets/.*})
                .to_return(body: asset_manager_response.to_json, status: 200)
        find('.attachments').first(:link, "delete").click
        expect(page.status_code).to eq(200)

        expect(page).not_to have_content('asylum-support-image.jpg')

        expect(page.status_code).to eq(200)
        expect(page).to have_content("Editing Example CMA Case")
      end

      scenario "previewing GovSpeak", js: true do
        fill_in "Body", with: "$CTA some text $CTA"

        click_link "Preview"

        within(".preview_container") do
          expect(page).to have_content("some text")
          expect(page).not_to have_content("$CTA")
        end

        fill_in "Body", with: "[InlineAttachment:asylum-support-image.jpg]"

        click_link "Preview"

        within(".preview_container") do
          expect(page).to have_content("asylum report image title")
          expect(page).not_to have_content("[InlineAttachment:")
        end

        fill_in "Body", with: "[link text](http://www.example.com)"

        click_link "Preview"

        within(".preview_container") do
          expect(page).to have_content("link text")
          expect(page).not_to have_content("http://www.example.com")
          expect(page).not_to have_content("some text")
        end
      end
    end
  end

  context "an unpublished document" do
    let(:cma_case) {
      FactoryGirl.create(
        :cma_case,
        :unpublished,
        title: "Example CMA Case",
        details: {},
        state_history: { "1" => "published", "2" => "unpublished", "3" => "draft" }
      )
    }

    scenario "showing the update type radio buttons" do
      within(".edit_document") do
        expect(page).to have_content('Only use for minor changes like fixes to typos, links, GOV.UK style or metadata.')
        expect(page).to have_content('This will notify subscribers to ')
        expect(page).to have_content('Update type minor')
        expect(page).to have_content('Update type major')
      end
    end

    scenario "insisting that an update type is chosen" do
      click_button "Save as draft"

      expect(page).to have_content("Please fix the following errors")
      expect(page).to have_content("Update type can't be blank")

      expect(page.status_code).to eq(422)
    end

    scenario "updating the title does not update the base path" do
      fill_in "Title", with: "New title"
      choose "Update type minor"
      click_button "Save as draft"
      changed_json = {
        "title" => "New title",
        "update_type" => "minor",
        "base_path" => "/cma-cases/example-document"
      }
      assert_publishing_api_put_content(content_id, request_json_includes(changed_json))
    end
  end

  context "a draft document" do
    scenario "not showing the update type radio buttons" do
      within(".edit_document") do
        expect(page).not_to have_content('Only use for minor changes like fixes to typos, links, GOV.UK style or metadata.')
        expect(page).not_to have_content('This will notify subscribers to ')
        expect(page).not_to have_content('Update type minor')
        expect(page).not_to have_content('Update type major')
      end
    end

    scenario "saving the document without an update type" do
      click_button "Save as draft"
      expect(page).to have_content("Updated Example CMA Case")
      expect(page.status_code).to eq(200)
    end
  end
end
