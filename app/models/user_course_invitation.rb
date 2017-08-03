# -*- encoding : utf-8 -*-
class UserCourseInvitation < CourseEnrollment
  require 'active_support'
  require 'securerandom'

  belongs_to :user

  before_validation :generate_token, :on => :create

  scope :invited, -> { where(state: 'invited')}
  scope :with_email, lambda { |email| where( :email => email.to_s) }
  scope :invitations_approved, -> { where(state: 'approved') }

  aasm column: :state do

    initial_state :waiting
    state :waiting
    # Envia e-mail avisando que ele foi convidado
    state :invited, :enter => :send_external_user_course_invitation
    # Convida o usuário (já dentro do Redu) para o curso
    state :approved, :enter => :create_user_course_association,
      :after_enter => Proc.new { |uci| uci.destroy }
    state :rejected
    state :failed

    event :invite do
      transitions :to => :invited, :from => [:waiting]
    end

    # Necessita que um usuário seja setado ANTES de chamar este método;
    # caso contrário, falha silenciosamente
    event :accept do
      transitions :to => :approved, :from => [:invited],
        :guard => Proc.new { |uci| uci.user }
    end

    event :deny do
      transitions :to => :rejected, :from => [:invited]
    end

    event :fail do
      transitions :to => :failed, :from => [:invited]
    end
  end

  validates_presence_of :token, :email, :course
  validates_uniqueness_of :token
  validates_uniqueness_of :email, :scope => :course_id
  validates_format_of :email,
    :with => /^([^@\s]+)@((?:[-a-z0-9A-Z]+\.)+[a-zA-Z]{2,})$/

  def send_external_user_course_invitation
    UserNotifier.delay(:queue => 'email').external_user_course_invitation(self, self.course)
  end

  protected
  def generate_token
    self.token = SecureRandom.base64(8).gsub("/","_").
      gsub(/=+$/,"")
  end

  def create_user_course_association
    self.course.invite(self.user)
  end
end
