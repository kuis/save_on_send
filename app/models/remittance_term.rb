class RemittanceTerm < ActiveRecord::Base
  belongs_to :receive_country, class_name: Country
  belongs_to :service_provider
  belongs_to :send_method, class_name: PaymentMethod
  belongs_to :receive_method, class_name: PaymentMethod

  monetize :fees_for_sending_cents

  # Use model level currency
  register_currency :usd

  def send_amount_with_fee(amount)
    amount_with_fee = amount + fees_for_sending
    amount_with_fee += (amount*fees_for_sending_percent)/100 if fees_for_sending_percent > 0
    amount_with_fee
  end

  def all_fees(amount)
    amount.to_i/100.0*fees_for_sending.to_i + fees_for_sending_percent + fx_markup
  end

  def estimated_receive_amount(amount, currency)
    (amount - amount*fx_markup/100).exchange_to(currency)
  end

  def self.least_expensive(amount_send: nil, receive_country: nil, receive_currency: nil, send_method: nil, receive_method: nil)
    return if amount_send.nil? || receive_country.nil? || receive_currency.nil?
  
    select_query = %Q{*, (#{amount_send.to_i}*fees_for_sending_cents::FLOAT/10000 + 
                          fees_for_sending_percent + fx_markup) as expense}

    least_expensive_services = RemittanceTerm.where(receive_country: receive_country, 
                         receive_currency: receive_currency)
                  .where("#{amount_send.to_i} >= send_amount_range_from AND " +
                         "#{amount_send.to_i} <= send_amount_range_to")
                  .select(select_query)
                  .order('expense')

    least_expensive_services = least_expensive_services.where(send_method: send_method) if send_method.present?
    least_expensive_services = least_expensive_services.where(receive_method: receive_method) if receive_method.present?
  
    least_expensive_services
  end

  def self.amount_save_on_transaction(amount_send: nil, receive_country: nil, receive_currency: nil, transaction_cost: nil)
    result = 0

    least_expensive_service = least_expensive(amount_send: amount_send, 
                                      receive_country: receive_country, 
                                      receive_currency: receive_currency).first
    
    if least_expensive_service
      least_expensive_transaction_cost = 
        Money.new(amount_send*least_expensive_service.expense/100, 'USD')
      
      if receive_currency != 'USD'
        least_expensive_transaction_cost = 
          least_expensive_transaction_cost.exchange_to(receive_currency)
      end
      
      result =  transaction_cost - least_expensive_transaction_cost
    end

    result
  end
  
  def self.import_from_csv(csv_path = nil)
    csv_file = csv_path.nil? ? Rails.root.join('db/seeds', 'remittance_terms.csv') : open(csv_path)

    events = CSV.read(csv_file, headers: :first_row)

    events.each do |data|
      # Receive country
      receive_country = Country.find_by(name: data['Receive country'])
      next if receive_country.nil?

      # Remit name
      service_provider = ServiceProvider.find_by(name: data['Remit name'])
      next if service_provider.nil?

      # Send method
      send_method = PaymentMethod.find_by(slug: data['Sending type'])
      next if send_method.nil?

      # Receive method
      receive_methods = data['Receiving type'].split(',')
      receive_methods.map!{|receive_method_slug| PaymentMethod.find_by(slug: receive_method_slug.strip)}.delete_if(&:nil?)
      next if receive_methods.empty?

      receive_methods.each do |receive_method|
        remittance_term_attrs = {
          receive_country: receive_country, 
          service_provider: service_provider,
          send_method: send_method,
          receive_method: receive_method,
          receive_currency: data['To which currency?'],
          send_amount_range_from: data['Send amount range ($USD) - From'].gsub(',', '_'),
          send_amount_range_to: data['Send amount range ($USD) - To'].gsub(',', '_'),
          fees_for_sending: data['Fees for sending - USD'] || 0,
          fees_for_sending_percent: data['Fees for sending - %'] || 0,
          fx_markup: data['FX markup'] || 0,
          duration: data['Send-to-receive - Duration (hours)'],
          documentation: data['Documentation requirements'],
          promotions: data['Promotions'],
          service_quality: data['Service quality']
        }

        RemittanceTerm.create(remittance_term_attrs)
      end
    end
  end
end