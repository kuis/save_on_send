class UserRecentTransactionsController < ApplicationController
  before_filter :authenticate_user!

  def new
    @user_recent_transaction = User::RecentTransaction.new(params[:user_recent_transaction])
  end

  def create
    #params[:user_recent_transaction][:documentation_requirements] = params[:user_recent_transaction][:documentation_requirements].join(',')

    # remove decimal part from amount send and receive
    params[:user_recent_transaction][:amount_sent] = params[:user_recent_transaction][:amount_sent].gsub(',', '_').to_i
    params[:user_recent_transaction][:amount_received] = params[:user_recent_transaction][:amount_received].gsub(',', '_').to_i

    # convert date from string
    begin
      params[:user_recent_transaction][:date] = Date.strptime(params[:user_recent_transaction][:date], '%m/%d/%Y') if params[:user_recent_transaction][:date]
    rescue
    end

    recent_transaction_attrs = params.require(:user_recent_transaction)
      .permit(:date, :currency, :amount_sent, :amount_received, :originating_source_of_funds_id,
              :service_provider_id, :destination_preference_for_funds_id, :fees_for_sending,
              :fees_for_receiving, :send_to_receive_duration, :send_to_receive_duration_interval,
              :documentation_requirements, :promotion,
              service_provider_attributes: [:name, :landing_page], 
              feedback_attributes: [:service_quality, :comments]
             )

    if recent_transaction_attrs[:service_provider_id].present? && recent_transaction_attrs[:service_provider_attributes].present?
      recent_transaction_attrs.delete(:service_provider_attributes)
    end

    if recent_transaction_attrs[:service_provider_attributes].present?
      recent_transaction_attrs[:service_provider_attributes][:created_by] = current_user
    end

    if recent_transaction_attrs[:feedback_attributes].present?
      recent_transaction_attrs[:feedback_attributes][:user] = current_user
    end

    @user_recent_transaction = current_user.recent_transactions.create(recent_transaction_attrs)

    if @user_recent_transaction.persisted?
      notice = I18n.t('notice.best_rate')

      more_money = RemittanceTerm.save_on_transaction(@user_recent_transaction)

      if more_money > 0
        destination_country = current_user.money_transfer_destination.name

        notice = I18n.t('notice.save_on_transaction',
                        destination_country: destination_country,
                        saving: more_money.to_i,
                        currency: more_money.currency.iso_code)
      end

      redirect_to(new_user_next_transfer_path, notice: notice)
    else
      render :new
    end
  end
end
