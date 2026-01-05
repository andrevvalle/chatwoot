class Api::V1::Accounts::Integrations::MercadoLivreController < Api::V1::Accounts::BaseController
  include MercadoLivre::IntegrationHelper
  before_action :fetch_hook, except: [:auth]
  before_action :validate_contact, only: [:orders]

  def auth
    state = generate_ml_token(Current.account.id)

    auth_url = 'https://auth.mercadolibre.com.br/authorization?'
    auth_url += URI.encode_www_form(
      response_type: 'code',
      client_id: client_id,
      redirect_uri: redirect_uri,
      state: state
    )

    render json: { redirect_url: auth_url }
  end

  def orders
    # Buscar pedidos do vendedor
    orders = fetch_orders
    render json: { orders: orders }
  rescue StandardError => e
    Rails.logger.error("Error fetching ML orders: #{e.message}")
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    @hook.destroy!
    head :ok
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def redirect_uri
    "#{ENV.fetch('FRONTEND_URL', '')}/mercado_livre/callback"
  end

  def contact
    @contact ||= Current.account.contacts.find_by(id: params[:contact_id])
  end

  def fetch_hook
    @hook = Integrations::Hook.find_by!(account: Current.account, app_id: 'mercado_livre')
  end

  def fetch_orders
    # Refresh token se necessário
    refresh_token_if_needed

    response = HTTParty.get(
      'https://api.mercadolibre.com/orders/search',
      headers: {
        'Authorization' => "Bearer #{@hook.access_token}"
      },
      query: {
        seller: @hook.reference_id,
        sort: 'date_desc',
        limit: 50
      }
    )

    unless response.success?
      Rails.logger.error("ML API Error: #{response.code} - #{response.body}")
      return []
    end

    orders = response.parsed_response['results'] || []

    # Adicionar URL admin
    orders.map do |order|
      order.merge(
        'admin_url' => "https://www.mercadolibre.com.br/ventas/#{order['id']}/detalle"
      )
    end
  end

  def refresh_token_if_needed
    # Mercado Livre tokens expiram em 6 horas
    expires_at = @hook.settings['token_expires_at'].to_i
    return if expires_at > Time.current.to_i + 300 # Refresh 5 minutos antes

    Rails.logger.info("Refreshing Mercado Livre token for account #{Current.account.id}")

    response = HTTParty.post(
      'https://api.mercadolibre.com/oauth/token',
      body: {
        grant_type: 'refresh_token',
        client_id: client_id,
        client_secret: client_secret,
        refresh_token: @hook.settings['refresh_token']
      }
    )

    if response.success?
      parsed = response.parsed_response
      @hook.update!(
        access_token: parsed['access_token'],
        settings: @hook.settings.merge(
          'refresh_token' => parsed['refresh_token'],
          'token_expires_at' => Time.current.to_i + parsed['expires_in']
        )
      )
      Rails.logger.info("Mercado Livre token refreshed successfully")
    else
      Rails.logger.error("Failed to refresh ML token: #{response.body}")
    end
  end

  def validate_contact
    return unless contact.blank?

    render json: { error: 'Contact not found' },
           status: :unprocessable_entity
  end
end
