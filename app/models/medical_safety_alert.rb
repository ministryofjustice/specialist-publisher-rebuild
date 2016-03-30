class MedicalSafetyAlert < Document
  validates :alert_type, presence: true
  validates :issued_date, presence: true, date: true

  FORMAT_SPECIFIC_FIELDS = [
    :alert_type,
    :issued_date,
    :medical_specialism,
  ]

  attr_accessor(*FORMAT_SPECIFIC_FIELDS)

  def initialize(params = {})
    super(params, FORMAT_SPECIFIC_FIELDS)
  end

  def self.publishing_api_document_type
    "medical_safety_alert"
  end
end