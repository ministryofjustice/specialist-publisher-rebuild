FactoryGirl.define do
  factory :user do
    sequence(:uid) { |n| "uid-#{n}" }
    sequence(:name) { |n| "Joe Bloggs #{n}" }
    sequence(:email) { |n| "joe#{n}@bloggs.com" }
    if defined?(GDS::SSO::Config)
      # Grant permission to signin to the app using the gem
      permissions { ["signin"] }
    end
  end

  factory :editor, parent: :user do
    permissions %w(signin editor)
  end

  factory :gds_editor, parent: :user do
    organisation_slug "government-digital-service"
    organisation_content_id "af07d5a5-df63-4ddc-9383-6a666845ebe9"
    permissions %w(signin gds_editor)
  end

  factory :cma_editor, parent: :editor do
    organisation_slug "competition-and-markets-authority"
    organisation_content_id "957eb4ec-089b-4f71-ba2a-dc69ac8919ea"
  end

  factory :writer, aliases: [:cma_writer], parent: :editor do
    organisation_slug "competition-and-markets-authority"
    organisation_content_id "957eb4ec-089b-4f71-ba2a-dc69ac8919ea"
    permissions %w(signin)
  end

  factory :aaib_editor, parent: :editor do
    organisation_slug "air-accidents-investigation-branch"
    organisation_content_id "38eb5d8f-2d89-480c-8655-e2e7ac23f8f4"
  end

  factory :dfid_editor, parent: :editor do
    organisation_slug "department-for-international-development"
    organisation_content_id "db994552-7644-404d-a770-a2fe659c661f"
  end
end
