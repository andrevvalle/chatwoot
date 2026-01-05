class MercadoLivre::CallbacksController < ApplicationController
  include MercadoLivre::IntegrationHelper
  skip_before_action :verify_authenticity_token, raise: false

  def show
    verify_account!

    # Trocar code por access_token
    response = HTTParty.post(
      'https://api.mercadolibre.com/oauth/token',
      body: {
        grant_type: 'authorization_code',
        client_id: client_id,
        client_secret: client_secret,
        code: params[:code],
        redirect_uri: "#{ENV.fetch('FRONTEND_URL', '')}/mercado_livre/callback"
      }
    )

    if response.success?
      handle_response(response.parsed_response)
    else
      Rails.logger.error("ML OAuth error: #{response.body}")
      redirect_to "#{ml_integration_url}?error=true"
    end
  rescue StandardError => e
    Rails.logger.error("ML callback error: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    redirect_to "#{redirect_uri}?error=true"
  end

  private

  def verify_account!
    @account_id = verify_ml_token(params[:state])
    raise StandardError, 'Invalid state parameter' if account.blank?
  end

  def handle_response(parsed_body)
    # Buscar user_id do vendedor
    user_response = HTTParty.get(
      'https://api.mercadolibre.com/users/me',
      headers: {
        'Authorization' => "Bearer #{parsed_body['access_token']}"
      }
    )

    unless user_response.success?
      Rails.logger.error("Failed to fetch user info: #{user_response.body}")
      redirect_to "#{ml_integration_url}?error=true"
      return
    end

    user_id = user_response.parsed_response['id']

    # Deletar hook existente se houver
    account.hooks.where(app_id: 'mercado_livre').destroy_all

    account.hooks.create!(
      app_id: 'mercado_livre',
      access_token: parsed_body['access_token'],
      status: 'enabled',
      reference_id: user_id.to_s,
      settings: {
        refresh_token: parsed_body['refresh_token'],
        token_expires_at: Time.current.to_i + parsed_body['expires_in'],
        scope: parsed_body['scope'],
        user_id: user_id
      }
    )

    redirect_to ml_integration_url
  end

  def account
    @account ||= Account.find(@account_id)
  end

  def ml_integration_url
    "#{ENV.fetch('FRONTEND_URL', nil)}/app/accounts/#{account.id}/settings/integrations/mercado_livre"
  end

  def redirect_uri
    return ml_integration_url if account

    ENV.fetch('FRONTEND_URL', nil)
  end
end
