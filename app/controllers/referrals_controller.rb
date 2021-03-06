class ReferralsController < ApplicationController
  before_filter :authenticate_user!

  def create
    referral_attrs = params.require(:referral).permit(:comments, :email)
  
    current_user.referrals.create(referral_attrs)

    redirect_to(root_path, notice: 'Thanks you for help! Your referral is successfully added to the our system.')
  end
end
