require 'spec_helper'

RSpec.describe Document do
  class MyDocumentType < Document
    def self.title
      "My Document Type"
    end

    attr_accessor :field1, :field2, :field3

    def initialize(params = {})
      super(params, [:field1, :field2, :field3])
    end
  end

  it "has a document_type for building URLs" do
    expect(MyDocumentType.slug).to eq("my-document-types")
  end

  it "has a document_type for fetching params of the format" do
    expect(MyDocumentType.document_type).to eq("my_document_type")
  end

  describe ".all" do
    it "makes a request to the publishing api with the correct params" do
      publishing_api = double(:publishing_api)
      allow(Services).to receive(:publishing_api).and_return(publishing_api)

      expect(publishing_api).to receive(:get_content_items)
        .with(
          publishing_app: "specialist-publisher",
          document_type: "my_document_type",
          fields: [
            :base_path,
            :content_id,
            :last_edited_at,
            :title,
            :publication_state,
            :state_history,
          ],
          page: 1,
          per_page: 20,
          order: "-last_edited_at",
          q: "foo",
        )

      MyDocumentType.all(1, 20, q: "foo")
    end
  end

  context "saving a new draft" do
    subject { MyDocumentType.new }

    before do
      stub_any_publishing_api_put_content
      stub_any_publishing_api_patch_links
      subject.title = "Title"
      subject.summary = "Summary"
      subject.body = "Body"
      subject.publication_state = nil
    end

    it "sends a correct document" do
      expect(subject.save).to be true
      assert_publishing_api_put_content(subject.content_id, request_json_includes(update_type: "major"))
    end
  end

  let(:finder_schema) {
    {
      base_path: "/my-document-types",
      filter: {
        document_type: "my_document_type",
      }
    }.deep_stringify_keys
  }

  let(:payload_attributes) {
    {
      document_type: "my_document_type",
      title: "Example document",
      description: "This is a summary",
      base_path: "/my-document-types/example-document",
      details: {
        body: [
          {
            content_type: "text/govspeak",
            content: "This is the body of an example document",
          },
          {
            content_type: "text/html",
            content: "<p>This is the body of an example document</p>\n",
          },
        ],
        metadata: {
          field1: "2015-12-01",
          field2: "open",
          field3: %w(x y z),
        }
      }
    }
  }
  let(:payload) { FactoryGirl.create(:document, payload_attributes) }
  let(:document) { MyDocumentType.from_publishing_api(payload) }

  before do
    allow_any_instance_of(FinderSchema).to receive(:load_schema_for).with("my_document_types").
      and_return(finder_schema)
  end

  describe ".from_publishing_api" do
    context "for a published document" do
      let(:payload) { FactoryGirl.create(:document, :published, payload_attributes) }

      it "sets the top-level attributes on a document" do
        expect(document.base_path).to eq(payload['base_path'])
        expect(document.content_id).to eq(payload['content_id'])
        expect(document.title).to eq(payload['title'])
        expect(document.summary).to eq(payload['description'])
        expect(document.publication_state).to eq(payload['publication_state'])
        expect(document.public_updated_at).to eq(payload['public_updated_at'])
        expect(document.first_published_at).to eq(payload['first_published_at'])
        expect(document.update_type).to eq(nil)
        expect(document.state_history).to eq(payload['state_history'])
      end

      context "when bulk published is true" do
        let(:payload_attributes) do
          {
            details: {
              metadata: {
                bulk_published: true
              }
            }
          }
        end

        specify { expect(document.bulk_published).to eq(true) }
      end

      context "when bulk published is not present in metadata" do
        let(:payload_attributes) do
          {
            details: {
              metadata: {}
            }
          }
        end

        specify { expect(document.bulk_published).to eq(false) }
      end

      context "when the body contains multiple content types" do
        let(:payload_attributes) do
          {
            details: {
              body: [
                { content_type: "text/govspeak", content: "# hello" },
                { content_type: "text/html", content: "<h1>hello</h1>" },
              ]
            }
          }
        end

        it "sets the body to the content of the govspeak type" do
          expect(document.body).to eq("# hello")
        end
      end

      context "when the body is just a string" do
        let(:payload_attributes) do
          {
            details: {
              body: "This is just a string.",
            }
          }
        end

        it "sets the body to that string" do
          expect(document.body).to eq("This is just a string.")
        end
      end

      it "sets its attachments collection from the payload" do
        expect(document.attachments).to be_an(AttachmentCollection)
      end

      it "sets format specific fields for the document subclass" do
        expect(document.format_specific_fields).to eq([:field1, :field2, :field3])

        expect(document.field1).to eq("2015-12-01")
        expect(document.field2).to eq("open")
        expect(document.field3).to eq(%w(x y z))
      end
    end

    context "when the document is redrafted" do
      let(:payload) do
        FactoryGirl.create(
          :document,
          :redrafted,
          payload_attributes.merge(update_type: "minor"),
        )
      end
      it "sets the update type" do
        expect(document.update_type).to eq(payload['update_type'])
      end

      context "when there is more than one item in the change history" do
        let(:payload_attributes) do
          {
            details: {
              change_history: [
                { note: "First published", public_timestamp: "2016-01-01" },
                { note: "Second note", public_timestamp: "2016-01-02" },
              ]
            }
          }
        end

        it "sets the change note to the second item in the change history" do
          document.update_type = "major"
          expect(document.change_note).to eq("Second note")
        end
      end

      context "when there is just one item in the change history" do
        specify { expect(document.change_note).to be_nil }
      end
    end

    context "when the document has a temporary update type" do
      let(:payload_attributes) { { details: { temporary_update_type: true } } }

      it "sets update type to nil and clears the temporary update type" do
        expect(document.update_type).to be_nil
        expect(document.temporary_update_type).to eq(false)
      end
    end
  end

  context "successful #publish" do
    let(:payload) { FactoryGirl.create(:document, :published, payload_attributes) }
    before do
      stub_any_publishing_api_put_content
      stub_any_publishing_api_patch_links
      stub_publishing_api_publish(document.content_id, {})
      publishing_api_has_item(payload)
      stub_any_rummager_post_with_queueing_enabled
      @email_alert_api = email_alert_api_accepts_alert
    end

    it "sends a payload to Publishing API" do
      expect(document.publish).to eq(true)

      assert_publishing_api_publish(document.content_id)
    end

    it "sends a payload to Rummager" do
      expect(document.publish).to eq(true)

      assert_rummager_posted_item(
        "title" => "Example document",
        "description" => "This is a summary",
        "indexable_content" => "This is the body of an example document",
        "link" => "/my-document-types/example-document",
        "public_timestamp" => "2015-11-16T11:53:30+00:00",
        "first_published_at" => "2015-11-15T00:00:00+00:00",
        "field1" => "2015-12-01",
        "field2" => "open",
      )
    end

    it "alerts the email API for major updates" do
      document.update_type = "major"

      expect(document.publish).to eq(true)

      assert_email_alert_sent(
        "tags" => {
          "format" => "my_document_type",
          "field1" => "2015-12-01",
          "field2" => "open",
          "field3" => %w(x y z),
        },
        "document_type" => "my_document_type"
      )
    end

    context "document is redrafted with a minor edit" do
      let(:minor_change_document) {
        MyDocumentType.from_publishing_api(
          FactoryGirl.create(:document,
            payload_attributes.merge(
              publication_state: 'published',
              update_type: 'minor',
              content_id: document.content_id
            ))
        )
      }

      it "doesn't alert the email API for minor updates" do
        expect(minor_change_document.publish).to eq(true)

        expect(@email_alert_api).to_not have_been_requested
      end
    end

    context "document has never been published" do
      let(:unpublished_document) {
        MyDocumentType.from_publishing_api(
          FactoryGirl.create(:document,
            payload_attributes.merge(
              first_published_at: nil,
              publication_state: 'draft',
              change_history: [],
              content_id: document.content_id
            ))
        )
      }

      it 'sends first_published_at to Rummager' do
        unpublished_document.publish
        assert_rummager_posted_item(
          "title" => "Example document",
          "description" => "This is a summary",
          "indexable_content" => "This is the body of an example document",
          "link" => "/my-document-types/example-document",
          "public_timestamp" => "2015-11-16T11:53:30+00:00",
          "first_published_at" => "2015-11-15T00:00:00+00:00",
          "field1" => "2015-12-01",
          "field2" => "open",
        )
      end

      it 'saves a "First published." change note before asking the api to publish' do
        Timecop.freeze(Time.parse("2015-12-18 10:12:26 UTC")) do
          unpublished_document.publish

          expected_change_history = [
            {
              "public_timestamp" => Time.current.iso8601,
              "note" => "First published.",
            },
          ]

          changed_json = {
            "update_type" => 'major',
            "details" => payload["details"].merge("change_history" => expected_change_history),
          }

          assert_publishing_api_put_content(unpublished_document.content_id, request_json_includes(changed_json))
        end
      end
    end

    shared_examples_for 'publishing changes to a document that has previously been published' do
      let(:published_document) {
        MyDocumentType.from_publishing_api(
          FactoryGirl.create(:document,
            :published,
            payload_attributes.merge(
              publication_state: publication_state,
              content_id: document.content_id
            ))
        )
      }

      it 'does not add a "First published" change note before asking the api to publish' do
        published_document.publish

        assert_no_publishing_api_put_content(published_document.content_id)
      end
    end

    context "when document is in live state" do
      let(:publication_state) { 'published' }
      it_behaves_like 'publishing changes to a document that has previously been published'
    end

    context 'when document is in redrafted state' do
      let(:publication_state) { 'draft' }
      it_behaves_like 'publishing changes to a document that has previously been published'
    end

    context 'when document is in unpublished state' do
      let(:publication_state) { 'unpublished' }
      it_behaves_like 'publishing changes to a document that has previously been published'
    end

    context 'when document is in superseded state' do
      let(:publication_state) { 'superseded' }
      it_behaves_like 'publishing changes to a document that has previously been published'
    end
  end

  context "unsuccessful #publish" do
    let(:payload) { FactoryGirl.create(:document, :published, payload_attributes) }

    it "notifies Airbrake and returns false if publishing-api does not return status 200" do
      expect(Airbrake).to receive(:notify)
      stub_any_publishing_api_put_content
      stub_any_publishing_api_patch_links
      stub_publishing_api_publish(document.content_id, {}, status: 503)
      stub_any_rummager_post_with_queueing_enabled
      expect(document.publish).to eq(false)
    end

    it "notifies Airbrake and returns false if rummager does not return status 200" do
      expect(Airbrake).to receive(:notify)
      stub_any_publishing_api_put_content
      stub_any_publishing_api_patch_links
      stub_publishing_api_publish(document.content_id, {})
      publishing_api_has_item(payload)
      stub_request(:post, %r{#{Plek.new.find('rummager')}/documents}).to_return(status: 503)
      expect(document.publish).to eq(false)
    end
  end

  describe "#unpublish" do
    before do
      publishing_api_has_item(payload)
      document = MyDocumentType.find(payload["content_id"])
      stub_publishing_api_unpublish(document.content_id, body: { type: 'gone' })
      stub_any_rummager_delete_content
    end

    it "sends correct payload to publishing api" do
      expect(document.unpublish).to eq(true)

      assert_publishing_api_unpublish(document.content_id)
    end

    it "sends a delete request to Rummager" do
      expect(document.unpublish).to eq(true)

      assert_rummager_deleted_content document.base_path
    end

    context "unsuccessful #unpublish" do
      it "notifies Airbrake and returns false if publishing-api does not return status 200" do
        expect(Airbrake).to receive(:notify)
        stub_publishing_api_unpublish(document.content_id, { body: { type: 'gone' } }, status: 409)
        expect(document.unpublish).to eq(false)
      end
    end
  end

  describe "#discard" do
    let(:content_id) { payload.fetch("content_id") }

    it "sends a discard draft request to the publishing api" do
      stub_publishing_api_discard_draft(content_id)
      document.discard
      assert_publishing_api_discard_draft(content_id)
    end

    it "returns true if the draft was discarded successfully" do
      stub_publishing_api_discard_draft(content_id)
      expect(document.discard).to eq(true)
    end

    it "returns false if the draft could not be discarded" do
      stub_request(:any, /discard/).to_raise(GdsApi::HTTPErrorResponse)
      expect(document.discard).to eq(false)
    end
  end

  describe "#save" do
    before do
      publishing_api_has_item(payload)
      Timecop.freeze(Time.parse("2015-12-18 10:12:26 UTC"))
    end

    it "saves document" do
      stub_any_publishing_api_put_content
      stub_any_publishing_api_patch_links

      c = MyDocumentType.find(payload["content_id"])
      expect(c.save).to eq(true)

      expected_payload = write_payload(payload.deep_stringify_keys)
      assert_publishing_api_put_content(c.content_id, expected_payload)
    end

    it "returns false without making any Publishing API calls if the document is invalid" do
      stub = stub_any_publishing_api_call

      document.title = nil # this is an invalid title
      expect(document).to_not be_valid

      expect(document.save).to be_falsey
      expect(stub).to_not have_been_requested
    end

    it "returns false if the Publishing API calls fail" do
      publishing_api_isnt_available
      expect(document.save).to be_falsey
    end

    describe "validations" do
      subject { Document.from_publishing_api(payload) }

      context "when the document is a draft" do
        let(:payload) { FactoryGirl.create(:document) }

        it "does not require an update_type" do
          subject.update_type = ""
          expect(subject).to be_valid
        end

        it "does not require a change_note" do
          subject.change_note = ""
          expect(subject).to be_valid
        end
      end

      context "when the document is published" do
        let(:payload) {
          FactoryGirl.create(:document, :published, state_history: { "1" => "published" })
        }

        it "requires an update_type" do
          subject.update_type = ""
          subject.change_note = "change note"

          expect(subject).not_to be_valid
        end

        it "requires a change_note" do
          subject.update_type = "major"
          subject.change_note = ""

          expect(subject).not_to be_valid
        end
      end

      context "when the document is unpublished" do
        let(:payload) {
          FactoryGirl.create(:document, :unpublished, state_history: { "1" => "published", "2" => "unpublished" })
        }

        it "requires an update_type" do
          subject.update_type = ""
          subject.change_note = "change note"

          expect(subject).not_to be_valid
        end

        it "requires a change_note" do
          subject.update_type = "major"
          subject.change_note = ""

          expect(subject).not_to be_valid
        end
      end

      context "when the document is brand new" do
        subject { Document.new }

        before do
          subject.title = "Title"
          subject.summary = "Summary"
          subject.body = "Body"
        end

        it "does not require an update_type" do
          subject.update_type = ""
          expect(subject).to be_valid
        end

        it "does not require a change_note" do
          subject.change_note = ""
          expect(subject).to be_valid
        end
      end
    end
  end

  describe ".find" do
    before do
      publishing_api_has_item(payload)
    end

    it "returns a document" do
      found_document = MyDocumentType.find(document.content_id)

      expect(found_document.base_path).to eq(payload["base_path"])
      expect(found_document.title).to     eq(payload["title"])
      expect(found_document.summary).to   eq(payload["description"])
      expect(found_document.body).to      eq(payload["details"]["body"][0]["content"])
      expect(found_document.field3).to    eq(payload["details"]["metadata"]["field3"])
    end

    describe "when called on the Document superclass" do
      it "returns an instance of the subclass with matching document_type" do
        found_document = Document.find(document.content_id)
        expect(found_document).to be_a(MyDocumentType)
      end
    end

    describe "when called on a class that mismatches the document_type" do
      it "raises a helpful error" do
        expect {
          CmaCase.find(document.content_id)
        }.to raise_error(/wrong type/)
      end
    end
  end

  describe "attachment methods" do
    let(:attachment) { Attachment.new }

    describe "#attachments=" do
      it "creates an AttachmentCollection with the given attachments" do
        subject.attachments = [attachment]

        expect(subject.attachments).to be_kind_of(AttachmentCollection)
        expect(subject.attachments.first).to eq(attachment)
      end
    end

    describe "#attachments" do
      it "returns an empty AttachmentCollection if none is set" do
        expect(subject.attachments).to be_kind_of(AttachmentCollection)
        expect(subject.attachments.count).to eq(0)
      end
    end

    describe "#upload_attachment" do
      before do
        subject.attachments = [attachment]
      end

      it "saves itself on successful attachment upload" do
        expect(subject.attachments).to receive(:upload).and_return(true)
        expect(subject).to receive(:save)
        subject.upload_attachment(attachment)
      end

      it "returns false on failed attachment upload" do
        expect(subject.attachments).to receive(:upload).and_return(false)

        expect(subject.upload_attachment(attachment)).to eq(false)
      end
    end

    describe '#delete_attachment' do
      before do
        subject.attachments = [attachment]
      end

      it 'deletes its attachment on a successful API call' do
        expect(subject.attachments).to receive(:remove).and_return(true)
        expect(subject).to receive(:save)
        subject.delete_attachment(attachment)
        expect subject.attachments.count == 0
      end

      it 'returns false and preserves its attachment on a failed call' do
        expect(subject.attachments).to receive(:remove).and_return(false)
        expect(subject.delete_attachment(attachment)).to eq(false)
        expect subject.attachments.count == 1
      end
    end
  end

  describe "#set_temporary_update_type!"do
    before { subject.publication_state = "published" }

    context "when the document has an update_type" do
      before do
        subject.update_type = "major"
        subject.set_temporary_update_type!
      end

      it "preserves the existing attributes" do
        expect(subject.update_type).to eq("major")
        expect(subject.temporary_update_type).to be_falsey
      end
    end

    context "when the document does not have an update_type" do
      before do
        subject.update_type = nil
        subject.set_temporary_update_type!
      end

      it "sets update_type to minor and temporary_update_type to true" do
        expect(subject.update_type).to eq("minor")
        expect(subject.temporary_update_type).to eq(true)
      end
    end
  end

  context "change_history" do
    subject { MyDocumentType.new }

    it "sets the change note when it is a major update" do
      subject.update_type = "major"
      subject.change_note = "some change note"

      expect(subject.change_note).to eq("some change note")
    end

    it "does not set the change note when it is a minor update" do
      subject.update_type = "minor"
      subject.change_note = "some change note"

      expect(subject.change_note).to be_nil
    end

    it "does not the change note when the update_type is not set" do
      subject.update_type = nil
      subject.change_note = "some change note"

      expect(subject.change_note).to be_nil
    end
  end

  context '#first_draft?' do
    subject { MyDocumentType.new }

    it "is true if there is no first_published_at" do
      subject.first_published_at = nil
      expect(subject.first_draft?).to eq(true)
    end

    it "is false if there is a first_published_at" do
      subject.first_published_at = "2015-11-15T00:00:00+00:00"
      expect(subject.first_draft?).to eq(false)
    end
  end
end
