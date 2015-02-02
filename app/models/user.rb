class User < ActiveRecord::Base
  US_PHONE_REGEX = /\A(?:\([2-9]\d{2}\)\ ?|[2-9]\d{2}(?:\-?|\ ?))[2-9]\d{2}[- ]?\d{4}\z/

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable,
         :confirmable, :lockable,
         :omniauthable, omniauth_providers: [:facebook]

  belongs_to :money_transfer_destination, class_name: Country

  has_many :recent_transactions, class: User::RecentTransaction
  has_many :next_transfers, class: User::NextTransfer

  has_many :feedbacks

  has_many :referrals

  belongs_to :level, class_name: User::Level

  mount_uploader :avatar, AvatarUploader  

  # validations
  #validates_presence_of :first_name
  #validates_presence_of :zipcode, unless: :skip_additional_info?
  validates_presence_of :money_transfer_destination, unless: :skip_additional_info?

  validates :phone, uniqueness: {case_sensitive: false}, format: {with: US_PHONE_REGEX}, 
    presence: true, if: :email_blank?

  validates_acceptance_of :accept_terms, :accept_emails, allow_nil: false, 
    accept: true, on: :create

  before_validation :fill_phone, on: :create

  def password_required?
    # Password is required if it is being set, but not for new records
    if !persisted? 
      false
    else
      !password.nil? || !password_confirmation.nil?
    end
  end

  def email_required?
    phone_blank?
  end

  def prefered_currency
    money_transfer_destination.try(:receive_currency)
  end

  def full_name
    [first_name, last_name].join(' ').strip
  end

  def skip_additional_info!
    @skip_additional_info = true
  end

  def skip_additional_info?
    @skip_additional_info
  end

  def complete?
    zipcode.present? && money_transfer_destination.present?
  end

  def phone_blank?
    phone.blank?
  end

  def email_blank?
    email.blank?
  end

  # new function to set the password without knowing the current password used in our confirmation controller. 
  def attempt_set_password(params)
    p = {}
    p[:password] = params[:password]
    p[:password_confirmation] = params[:password_confirmation]
    update_attributes(p)
  end
  # new function to return whether a password has been set
  def has_no_password?
    self.encrypted_password.blank?
  end

  def password_match?
    password == password_confirmation
  end

  # new function to provide access to protected method unless_confirmed
  def only_if_unconfirmed
    pending_any_confirmation {yield}    
  end

  def self.from_omniauth(auth)
    where(provider: auth.provider, uid: auth.uid).first_or_create do |user|
      user.email = auth.info.email
      user.password = Devise.friendly_token[0,20]
      user.first_name = auth.info.first_name
      user.last_name = auth.info.last_name
      user.skip_additional_info!
    end
  end

  private
  def fill_phone
    if email.match(US_PHONE_REGEX)
      self.phone = email
      self.email = ''
    end
  end
end
