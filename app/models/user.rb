# frozen_string_literal: true

# Person responsible for subsidy management for one or more businesses
class User < UuidApplicationRecord
  # Include default devise modules. Others available are:
  # :lockable, :omniauthable, :rememberable, :timeoutable, :trackable
  devise :confirmable,
         :database_authenticatable,
         :registerable,
         :recoverable,
         :trackable,
         :validatable,
         :jwt_authenticatable,
         jwt_revocation_strategy: BlockedToken

  has_many :businesses, dependent: :restrict_with_error
  has_many :children, through: :businesses, dependent: :restrict_with_error
  has_many :child_approvals, through: :children, dependent: :restrict_with_error
  has_many :nebraska_approval_amounts, through: :child_approvals, dependent: :restrict_with_error
  has_many :approvals, through: :child_approvals, dependent: :restrict_with_error
  has_many :service_days, through: :children, dependent: :restrict_with_error
  has_many :schedules, through: :children, dependent: :restrict_with_error

  accepts_nested_attributes_for :businesses, :children, :child_approvals, :approvals, :nebraska_approval_amounts

  validates :active, inclusion: { in: [true, false] }
  validates :email, presence: true, uniqueness: true
  validates :full_name, presence: true
  validates :greeting_name, presence: true
  validates :language, presence: true
  validates :organization, presence: true
  validates :opt_in_email, inclusion: { in: [true, false] }
  validates :opt_in_text, inclusion: { in: [true, false] }
  validates :phone_number, uniqueness: true, allow_nil: true
  validates :service_agreement_accepted, presence: true
  validates :timezone, presence: true

  scope :active, -> { where(active: true) }

  scope :with_dashboard_case,
        lambda {
          distinct
            .joins(:businesses)
            .includes(:child_approvals, :approvals)
        }

  # format phone numbers - remove any non-digit characters
  def phone_number=(value)
    super(value.blank? ? nil : value.gsub(/[^\d]/, ''))
  end

  # don't return the user's admin status in the API JSON
  def as_json(_options = {})
    super(except: [:admin])
  end

  def state
    return @state if @state

    return '' unless businesses

    @state = businesses&.first&.state || ''
  end

  # return the user's latest attendance check_in in UTC
  def latest_service_day_in_month(filter_date)
    filter_date ||= Time.current
    service_days.for_month(filter_date.in_time_zone(timezone)).order(date: :desc).first&.date
  end

  def first_approval_effective_date
    return if approvals.blank?

    approvals.order(effective_on: :desc).first.effective_on
  end
end

# == Schema Information
#
# Table name: users
#
#  id                         :uuid             not null, primary key
#  active                     :boolean          default(TRUE), not null
#  admin                      :boolean          default(FALSE), not null
#  confirmation_sent_at       :datetime
#  confirmation_token         :string
#  confirmed_at               :datetime
#  current_sign_in_at         :datetime
#  current_sign_in_ip         :inet
#  deleted_at                 :date
#  email                      :string           not null
#  encrypted_password         :string           default(""), not null
#  full_name                  :string           not null
#  greeting_name              :string           not null
#  language                   :string           not null
#  last_sign_in_at            :datetime
#  last_sign_in_ip            :inet
#  opt_in_email               :boolean          default(TRUE), not null
#  opt_in_text                :boolean          default(TRUE), not null
#  organization               :string           not null
#  phone_number               :string
#  phone_type                 :string
#  remember_created_at        :datetime
#  reset_password_sent_at     :datetime
#  reset_password_token       :string
#  service_agreement_accepted :boolean          default(FALSE), not null
#  sign_in_count              :integer          default(0), not null
#  timezone                   :string           not null
#  unconfirmed_email          :string
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#
# Indexes
#
#  index_users_on_confirmation_token    (confirmation_token)
#  index_users_on_email                 (email) UNIQUE
#  index_users_on_phone_number          (phone_number) UNIQUE
#  index_users_on_reset_password_token  (reset_password_token)
#
