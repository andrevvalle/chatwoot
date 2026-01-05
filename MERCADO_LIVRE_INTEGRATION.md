# Integração Mercado Livre - Análise Técnica

## 📋 Análise da Integração Shopify (Exemplo Base)

### Arquitetura Geral

A integração do Shopify segue um padrão de **OAuth 2.0** com os seguintes componentes:

```
┌─────────────────────────────────────────────────────────────────┐
│                     ARQUITETURA SHOPIFY                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  1. Frontend (Vue 3)                                             │
│     └── Shopify.vue (configuração da integração)                │
│     └── ShopifyOrdersList.vue (exibir pedidos)                  │
│     └── ShopifyOrderItem.vue (item individual)                  │
│                                                                   │
│  2. API Frontend                                                 │
│     └── integrations/shopify.js (chamadas HTTP)                 │
│                                                                   │
│  3. Backend Controllers                                          │
│     └── Api::V1::Accounts::Integrations::ShopifyController      │
│         ├── auth (iniciar OAuth)                                │
│         ├── orders (buscar pedidos)                             │
│         └── destroy (remover integração)                        │
│     └── Shopify::CallbacksController (OAuth callback)           │
│                                                                   │
│  4. Helpers                                                      │
│     └── Shopify::IntegrationHelper                              │
│         ├── generate_shopify_token (JWT para state)            │
│         └── verify_shopify_token (validar callback)            │
│                                                                   │
│  5. Models                                                       │
│     └── Integrations::Hook (armazena credenciais)               │
│     └── Integrations::App (configuração da app)                 │
│                                                                   │
│  6. Configuração                                                 │
│     └── config/integration/apps.yml (metadados)                 │
│     └── GlobalConfig (SHOPIFY_CLIENT_ID, SHOPIFY_CLIENT_SECRET)│
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔍 Componentes Detalhados

### 1. **Configuração (apps.yml)**

```yaml
shopify:
  id: shopify
  logo: shopify.png
  i18n_key: shopify
  hook_type: account
  allow_multiple_hooks: false
```

**Campos importantes:**
- `id`: identificador único da integração
- `hook_type`: `account` (nível de conta) ou `inbox` (nível de caixa de entrada)
- `allow_multiple_hooks`: se permite múltiplas conexões

---

### 2. **Model: Integrations::Hook**

Armazena as credenciais e tokens de acesso:

```ruby
# Schema
{
  app_id: 'shopify',           # ID da integração
  account_id: 1,                # Conta Chatwoot
  access_token: 'encrypted',    # Token OAuth (criptografado)
  reference_id: 'store.myshopify.com',  # Domínio da loja
  settings: {                   # Configurações extras
    scope: 'read_orders,read_customers'
  },
  status: 'enabled',            # enabled/disabled
  hook_type: 'account'          # account/inbox
}
```

---

### 3. **Fluxo OAuth Completo**

#### **Passo 1: Iniciar Autenticação**

```ruby
# app/controllers/api/v1/accounts/integrations/shopify_controller.rb
def auth
  shop_domain = params[:shop_domain]  # 'loja.myshopify.com'

  # Gera token JWT com account_id para validar callback
  state = generate_shopify_token(Current.account.id)

  # Constrói URL de autorização
  auth_url = "https://#{shop_domain}/admin/oauth/authorize?"
  auth_url += URI.encode_www_form(
    client_id: client_id,
    scope: REQUIRED_SCOPES.join(','),  # ['read_customers', 'read_orders']
    redirect_uri: redirect_uri,         # '/shopify/callback'
    state: state                        # JWT com account_id
  )

  render json: { redirect_url: auth_url }
end
```

**Frontend dispara:**
```javascript
// app/javascript/dashboard/api/integrations.js
connectShopify({ shopDomain }) {
  return axios.post(`${this.baseUrl()}/integrations/shopify/auth`, {
    shop_domain: shopDomain,
  });
}
```

#### **Passo 2: Callback OAuth**

```ruby
# app/controllers/shopify/callbacks_controller.rb
def show
  # Valida o state (JWT) para recuperar account_id
  @account_id = verify_shopify_token(params[:state])

  # Troca o código por access_token
  @response = oauth_client.auth_code.get_token(
    params[:code],
    redirect_uri: '/shopify/callback'
  )

  # Salva credenciais no banco
  account.hooks.create!(
    app_id: 'shopify',
    access_token: parsed_body['access_token'],
    status: 'enabled',
    reference_id: params[:shop],  # domínio da loja
    settings: {
      scope: parsed_body['scope']
    }
  )

  # Redireciona para página de integração
  redirect_to shopify_integration_url
end
```

---

### 4. **Buscar Pedidos (API Resource)**

```ruby
# app/controllers/api/v1/accounts/integrations/shopify_controller.rb
def orders
  # 1. Busca cliente por email/telefone do contato
  customers = fetch_customers
  return render json: { orders: [] } if customers.empty?

  # 2. Busca pedidos do cliente
  orders = fetch_orders(customers.first['id'])
  render json: { orders: orders }
end

private

def fetch_customers
  query = []
  query << "email:#{contact.email}" if contact.email.present?
  query << "phone:#{contact.phone_number}" if contact.phone_number.present?

  shopify_client.get(
    path: 'customers/search.json',
    query: {
      query: query.join(' OR '),
      fields: 'id,email,phone'
    }
  ).body['customers'] || []
end

def fetch_orders(customer_id)
  orders = shopify_client.get(
    path: 'orders.json',
    query: {
      customer_id: customer_id,
      status: 'any',
      fields: 'id,email,created_at,total_price,currency,fulfillment_status,financial_status'
    }
  ).body['orders'] || []

  # Adiciona URL admin
  orders.map do |order|
    order.merge('admin_url' => "https://#{@hook.reference_id}/admin/orders/#{order['id']}")
  end
end

def shopify_client
  @shopify_client ||= ShopifyAPI::Clients::Rest::Admin.new(
    session: shopify_session
  )
end

def shopify_session
  ShopifyAPI::Auth::Session.new(
    shop: @hook.reference_id,
    access_token: @hook.access_token
  )
end
```

---

### 5. **Frontend: Exibir Pedidos**

```vue
<!-- ShopifyOrdersList.vue -->
<script setup>
import ShopifyAPI from '../../../api/integrations/shopify';

const fetchOrders = async () => {
  try {
    loading.value = true;
    const response = await ShopifyAPI.getOrders(props.contactId);
    orders.value = response.data.orders;
  } catch (e) {
    error.value = e.response?.data?.error;
  } finally {
    loading.value = false;
  }
};
</script>

<template>
  <div v-if="!orders.length">
    No orders found
  </div>
  <ShopifyOrderItem
    v-for="order in orders"
    :key="order.id"
    :order="order"
  />
</template>
```

```vue
<!-- ShopifyOrderItem.vue -->
<template>
  <div class="order-item">
    <a :href="order.admin_url" target="_blank">
      Order #{{ order.id }}
    </a>
    <div>{{ formatCurrency(order.total_price, order.currency) }}</div>
    <div>{{ order.financial_status }}</div>
    <div>{{ order.fulfillment_status }}</div>
  </div>
</template>
```

---

## 🛠️ Implementação Mercado Livre

### **Diferenças Chave: Shopify vs Mercado Livre**

| Aspecto | Shopify | Mercado Livre |
|---------|---------|---------------|
| **OAuth** | OAuth 2.0 padrão | OAuth 2.0 com refresh token |
| **Endpoint Base** | `https://{shop}.myshopify.com` | `https://api.mercadolibre.com` |
| **Identificador** | Domínio da loja | `user_id` |
| **Scopes** | `read_orders`, `read_customers` | `read`, `offline_access` |
| **API Clients** | Gem `shopify_api` | HTTParty ou REST client |
| **Tokens** | Não expira | Expira em 6h (precisa refresh) |

---

## 📝 Passo a Passo: Integração Mercado Livre

### **1. Adicionar ao apps.yml**

```yaml
# config/integration/apps.yml
mercado_livre:
  id: mercado_livre
  logo: mercado_livre.png
  i18n_key: mercado_livre
  hook_type: account
  allow_multiple_hooks: false
```

### **2. Criar Helper**

```ruby
# app/helpers/mercado_livre/integration_helper.rb
module MercadoLivre::IntegrationHelper
  REQUIRED_SCOPES = %w[read offline_access].freeze

  def generate_ml_token(account_id)
    return if client_secret.blank?

    JWT.encode(token_payload(account_id), client_secret, 'HS256')
  end

  def verify_ml_token(token)
    return if token.blank? || client_secret.blank?

    decode_token(token, client_secret)
  end

  private

  def client_id
    @client_id ||= GlobalConfigService.load('MERCADO_LIVRE_CLIENT_ID', nil)
  end

  def client_secret
    @client_secret ||= GlobalConfigService.load('MERCADO_LIVRE_CLIENT_SECRET', nil)
  end

  def token_payload(account_id)
    {
      sub: account_id,
      iat: Time.current.to_i
    }
  end

  def decode_token(token, secret)
    JWT.decode(
      token,
      secret,
      true,
      {
        algorithm: 'HS256',
        verify_expiration: true
      }
    ).first['sub']
  rescue StandardError => e
    Rails.logger.error("Error verifying ML token: #{e.message}")
    nil
  end
end
```

### **3. Criar Controller de Autenticação**

```ruby
# app/controllers/api/v1/accounts/integrations/mercado_livre_controller.rb
class Api::V1::Accounts::Integrations::MercadoLivreController < Api::V1::Accounts::BaseController
  include MercadoLivre::IntegrationHelper
  before_action :fetch_hook, except: [:auth]
  before_action :validate_contact, only: [:orders]

  def auth
    state = generate_ml_token(Current.account.id)

    auth_url = "https://auth.mercadolibre.com.br/authorization?"
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
      "https://api.mercadolibre.com/orders/search",
      headers: {
        'Authorization' => "Bearer #{@hook.access_token}"
      },
      query: {
        seller: @hook.reference_id,  # user_id do vendedor
        sort: 'date_desc',
        limit: 50
      }
    )

    return [] unless response.success?

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
    return if @hook.settings['token_expires_at'].to_i > Time.current.to_i

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
    end
  end

  def validate_contact
    return unless contact.blank?

    render json: { error: 'Contact not found' },
           status: :unprocessable_entity
  end
end
```

### **4. Criar Controller de Callback**

```ruby
# app/controllers/mercado_livre/callbacks_controller.rb
class MercadoLivre::CallbacksController < ApplicationController
  include MercadoLivre::IntegrationHelper

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
        redirect_uri: redirect_uri
      }
    )

    if response.success?
      handle_response(response.parsed_response)
    else
      redirect_to "#{redirect_uri}?error=true"
    end
  rescue StandardError => e
    Rails.logger.error("ML callback error: #{e.message}")
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

    user_id = user_response.parsed_response['id']

    account.hooks.create!(
      app_id: 'mercado_livre',
      access_token: parsed_body['access_token'],
      status: 'enabled',
      reference_id: user_id.to_s,
      settings: {
        refresh_token: parsed_body['refresh_token'],
        token_expires_at: Time.current.to_i + parsed_body['expires_in'],
        scope: parsed_body['scope']
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
```

### **5. Adicionar Rotas**

```ruby
# config/routes.rb

# Dentro de namespace :api do
#   namespace :v1 do
#     resources :accounts do
#       namespace :integrations do
resource :mercado_livre, controller: 'mercado_livre', only: [:destroy] do
  collection do
    post :auth
    get :orders
  end
end

# No final do arquivo (fora de namespace)
namespace :mercado_livre do
  resource :callback, only: [:show]
end
```

### **6. Frontend: API Client**

```javascript
// app/javascript/dashboard/api/integrations/mercado_livre.js
import ApiClient from '../ApiClient';

class MercadoLivreAPI extends ApiClient {
  constructor() {
    super('integrations/mercado_livre', { accountScoped: true });
  }

  getOrders(contactId) {
    return axios.get(`${this.url}/orders`, {
      params: { contact_id: contactId },
    });
  }
}

export default new MercadoLivreAPI();
```

```javascript
// app/javascript/dashboard/api/integrations.js
// Adicionar método
connectMercadoLivre() {
  return axios.post(`${this.baseUrl()}/integrations/mercado_livre/auth`);
}
```

### **7. Frontend: Componente de Configuração**

```vue
<!-- app/javascript/dashboard/routes/dashboard/settings/integrations/MercadoLivre.vue -->
<script setup>
import { ref, computed, onMounted } from 'vue';
import {
  useFunctionGetter,
  useMapGetter,
  useStore,
} from 'dashboard/composables/store';
import Integration from './Integration.vue';
import Spinner from 'shared/components/Spinner.vue';
import integrationAPI from 'dashboard/api/integrations';
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({
  error: {
    type: String,
    default: '',
  },
});

const store = useStore();
const integrationLoaded = ref(false);
const isSubmitting = ref(false);
const integration = useFunctionGetter('integrations/getIntegration', 'mercado_livre');
const uiFlags = useMapGetter('integrations/getUIFlags');

const integrationAction = computed(() => {
  if (integration.value.enabled) {
    return 'disconnect';
  }
  return 'connect';
});

const handleConnect = async () => {
  try {
    isSubmitting.value = true;
    const { data } = await integrationAPI.connectMercadoLivre();

    if (data.redirect_url) {
      window.location.href = data.redirect_url;
    }
  } catch (error) {
    console.error('Error connecting to Mercado Livre:', error);
  } finally {
    isSubmitting.value = false;
  }
};

const initializeMercadoLivreIntegration = async () => {
  await store.dispatch('integrations/get', 'mercado_livre');
  integrationLoaded.value = true;
};

onMounted(() => {
  initializeMercadoLivreIntegration();
});
</script>

<template>
  <div class="flex-grow flex-shrink p-4 overflow-auto max-w-6xl mx-auto">
    <div
      v-if="integrationLoaded && !uiFlags.isCreatingMercadoLivre"
      class="flex flex-col gap-6"
    >
      <Integration
        :integration-id="integration.id"
        :integration-logo="integration.logo"
        :integration-name="integration.name"
        :integration-description="integration.description"
        :integration-enabled="integration.enabled"
        :integration-action="integrationAction"
        :delete-confirmation-text="{
          title: $t('INTEGRATION_SETTINGS.MERCADO_LIVRE.DELETE.TITLE'),
          message: $t('INTEGRATION_SETTINGS.MERCADO_LIVRE.DELETE.MESSAGE'),
        }"
      >
        <template #action>
          <Button
            teal
            :label="$t('INTEGRATION_SETTINGS.CONNECT.BUTTON_TEXT')"
            :loading="isSubmitting"
            @click="handleConnect"
          />
        </template>
      </Integration>
      <div
        v-if="error"
        class="flex items-center justify-center flex-1 outline outline-n-container outline-1 bg-n-alpha-3 rounded-md shadow p-6"
      >
        <p class="text-n-ruby-9">
          {{ $t('INTEGRATION_SETTINGS.MERCADO_LIVRE.ERROR') }}
        </p>
      </div>
    </div>

    <div v-else class="flex items-center justify-center flex-1">
      <Spinner size="" color-scheme="primary" />
    </div>
  </div>
</template>
```

### **8. Frontend: Lista de Pedidos**

```vue
<!-- app/javascript/dashboard/components/widgets/conversation/MercadoLivreOrdersList.vue -->
<script setup>
import { ref, watch, computed } from 'vue';
import { useFunctionGetter } from 'dashboard/composables/store';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import MercadoLivreAPI from '../../../api/integrations/mercado_livre';
import MercadoLivreOrderItem from './MercadoLivreOrderItem.vue';

const props = defineProps({
  contactId: {
    type: [Number, String],
    required: true,
  },
});

const contact = useFunctionGetter('contacts/getContact', props.contactId);

const hasSearchableInfo = computed(
  () => !!contact.value?.email || !!contact.value?.phone_number
);

const orders = ref([]);
const loading = ref(true);
const error = ref('');

const fetchOrders = async () => {
  try {
    loading.value = true;
    const response = await MercadoLivreAPI.getOrders(props.contactId);
    orders.value = response.data.orders;
  } catch (e) {
    error.value =
      e.response?.data?.error || 'CONVERSATION_SIDEBAR.MERCADO_LIVRE.ERROR';
  } finally {
    loading.value = false;
  }
};

watch(
  () => props.contactId,
  () => {
    if (hasSearchableInfo.value) {
      fetchOrders();
    }
  },
  { immediate: true }
);
</script>

<template>
  <div class="px-4 py-2 text-n-slate-12">
    <div v-if="!hasSearchableInfo" class="text-center text-n-slate-12">
      {{ $t('CONVERSATION_SIDEBAR.MERCADO_LIVRE.NO_ORDERS') }}
    </div>
    <div v-else-if="loading" class="flex justify-center items-center p-4">
      <Spinner size="32" class="text-n-brand" />
    </div>
    <div v-else-if="error" class="text-center text-n-ruby-12">
      {{ error }}
    </div>
    <div v-else-if="!orders.length" class="text-center text-n-slate-12">
      {{ $t('CONVERSATION_SIDEBAR.MERCADO_LIVRE.NO_ORDERS') }}
    </div>
    <div v-else>
      <MercadoLivreOrderItem
        v-for="order in orders"
        :key="order.id"
        :order="order"
      />
    </div>
  </div>
</template>
```

```vue
<!-- app/javascript/dashboard/components/widgets/conversation/MercadoLivreOrderItem.vue -->
<script setup>
import { computed } from 'vue';
import { format } from 'date-fns';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  order: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();

const formatDate = dateString => {
  return format(new Date(dateString), 'dd/MM/yyyy HH:mm');
};

const formatCurrency = (amount, currency) => {
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: currency || 'BRL',
  }).format(amount);
};

const getStatusClass = status => {
  const classes = {
    paid: 'bg-n-teal-5 text-n-teal-12',
    pending: 'bg-n-amber-5 text-n-amber-12',
    cancelled: 'bg-n-ruby-5 text-n-ruby-12',
  };
  return classes[status] || 'bg-n-solid-3 text-n-slate-12';
};

const statusLabel = computed(() => {
  const status = props.order.status;
  return t(`CONVERSATION_SIDEBAR.MERCADO_LIVRE.STATUS.${status.toUpperCase()}`);
});
</script>

<template>
  <div
    class="py-3 border-b border-n-weak last:border-b-0 flex flex-col gap-1.5"
  >
    <div class="flex justify-between items-center">
      <div class="font-medium flex">
        <a
          :href="order.admin_url"
          target="_blank"
          rel="noopener noreferrer"
          class="hover:underline text-n-slate-12 cursor-pointer truncate"
        >
          Pedido #{{ order.id }}
          <i class="i-lucide-external-link pl-5" />
        </a>
      </div>
      <div
        :class="getStatusClass(order.status)"
        class="text-xs px-2 py-1 rounded capitalize truncate"
        :title="statusLabel"
      >
        {{ statusLabel }}
      </div>
    </div>
    <div class="text-sm text-n-slate-12">
      <span class="text-n-slate-11 border-r border-n-weak pr-2">
        {{ formatDate(order.date_created) }}
      </span>
      <span class="text-n-slate-11 pl-2">
        {{ formatCurrency(order.total_amount, order.currency_id) }}
      </span>
    </div>
    <div v-if="order.buyer">
      <span class="text-xs text-n-slate-11">
        {{ order.buyer.nickname }}
      </span>
    </div>
  </div>
</template>
```

### **9. Traduções (i18n)**

```json
// app/javascript/dashboard/i18n/locale/en/integrations.json
{
  "INTEGRATION_SETTINGS": {
    "MERCADO_LIVRE": {
      "DELETE": {
        "TITLE": "Delete Mercado Livre Integration",
        "MESSAGE": "Are you sure you want to delete the Mercado Livre integration?"
      },
      "ERROR": "There was an error connecting to Mercado Livre. Please try again or contact support if the issue persists."
    }
  }
}
```

```json
// app/javascript/dashboard/i18n/locale/en/conversation.json
{
  "CONVERSATION_SIDEBAR": {
    "MERCADO_LIVRE": {
      "NO_ORDERS": "No orders found for this contact",
      "ERROR": "Error loading orders",
      "STATUS": {
        "PAID": "Paid",
        "PENDING": "Pending",
        "CANCELLED": "Cancelled",
        "CONFIRMED": "Confirmed"
      }
    }
  }
}
```

### **10. Adicionar Rota no Frontend**

```javascript
// app/javascript/dashboard/routes/dashboard/settings/integrations/integrations.routes.js
{
  path: 'mercado_livre',
  name: 'mercado_livre_integration',
  roles: ['administrator'],
  component: () => import('./MercadoLivre.vue'),
  props: route => ({ error: route.query.error === 'true' }),
},
```

### **11. Configurar Variáveis de Ambiente**

```bash
# .env
MERCADO_LIVRE_CLIENT_ID=your_client_id_here
MERCADO_LIVRE_CLIENT_SECRET=your_client_secret_here
```

### **12. Adicionar ao InstallationConfig**

```yaml
# config/installation_config.yml
- name: MERCADO_LIVRE_CLIENT_ID
  value: ''
  display_title: 'Mercado Livre Client ID'
  description: 'Client ID from Mercado Livre Developer Portal'
  secret: false

- name: MERCADO_LIVRE_CLIENT_SECRET
  value: ''
  display_title: 'Mercado Livre Client Secret'
  description: 'Client Secret from Mercado Livre Developer Portal'
  secret: true
```

### **13. Habilitar Feature Flag (se necessário)**

```ruby
# app/models/integrations/app.rb
def active?(account)
  case params[:id]
  # ... outros casos ...
  when 'mercado_livre'
    mercado_livre_enabled?(account)
  else
    true
  end
end

private

def mercado_livre_enabled?(account)
  GlobalConfigService.load('MERCADO_LIVRE_CLIENT_ID', nil).present?
end
```

---

## 📚 Recursos da API Mercado Livre

### **Endpoints Principais**

```ruby
# Autenticação
POST https://api.mercadolibre.com/oauth/token
  grant_type: authorization_code
  client_id: YOUR_CLIENT_ID
  client_secret: YOUR_CLIENT_SECRET
  code: AUTHORIZATION_CODE
  redirect_uri: YOUR_REDIRECT_URI

# Refresh Token
POST https://api.mercadolibre.com/oauth/token
  grant_type: refresh_token
  client_id: YOUR_CLIENT_ID
  client_secret: YOUR_CLIENT_SECRET
  refresh_token: REFRESH_TOKEN

# Dados do Usuário
GET https://api.mercadolibre.com/users/me
  Authorization: Bearer ACCESS_TOKEN

# Buscar Pedidos
GET https://api.mercadolibre.com/orders/search
  seller: USER_ID
  sort: date_desc
  limit: 50
  Authorization: Bearer ACCESS_TOKEN

# Detalhes de um Pedido
GET https://api.mercadolibre.com/orders/{order_id}
  Authorization: Bearer ACCESS_TOKEN
```

### **Estrutura de Pedido (Order)**

```json
{
  "id": 2000003508808315,
  "status": "paid",
  "status_detail": null,
  "date_created": "2021-11-18T09:45:48.000-04:00",
  "date_closed": "2021-11-18T09:45:48.000-04:00",
  "order_items": [
    {
      "item": {
        "id": "MLB1234567890",
        "title": "Product Title",
        "variation_id": 123456
      },
      "quantity": 1,
      "unit_price": 100.00,
      "full_unit_price": 100.00
    }
  ],
  "total_amount": 100.00,
  "currency_id": "BRL",
  "buyer": {
    "id": 12345678,
    "nickname": "BUYER_NICKNAME",
    "email": "buyer@example.com",
    "phone": {
      "area_code": "11",
      "number": "98765-4321"
    }
  },
  "seller": {
    "id": 87654321,
    "nickname": "SELLER_NICKNAME"
  },
  "payments": [
    {
      "id": 123456789,
      "status": "approved",
      "transaction_amount": 100.00
    }
  ],
  "shipping": {
    "id": 123456789012,
    "status": "pending"
  }
}
```

---

## ✅ Checklist de Implementação

### Backend
- [ ] Criar `app/helpers/mercado_livre/integration_helper.rb`
- [ ] Criar `app/controllers/api/v1/accounts/integrations/mercado_livre_controller.rb`
- [ ] Criar `app/controllers/mercado_livre/callbacks_controller.rb`
- [ ] Adicionar rotas em `config/routes.rb`
- [ ] Atualizar `config/integration/apps.yml`
- [ ] Atualizar `config/installation_config.yml`
- [ ] Adicionar logo `public/dashboard/images/integrations/mercado_livre.png`
- [ ] Adicionar `MERCADO_LIVRE_CLIENT_ID` e `MERCADO_LIVRE_CLIENT_SECRET` ao `.env`
- [ ] Testar fluxo OAuth completo
- [ ] Testar busca de pedidos
- [ ] Testar refresh token

### Frontend
- [ ] Criar `app/javascript/dashboard/api/integrations/mercado_livre.js`
- [ ] Atualizar `app/javascript/dashboard/api/integrations.js`
- [ ] Criar `app/javascript/dashboard/routes/dashboard/settings/integrations/MercadoLivre.vue`
- [ ] Criar `app/javascript/dashboard/components/widgets/conversation/MercadoLivreOrdersList.vue`
- [ ] Criar `app/javascript/dashboard/components/widgets/conversation/MercadoLivreOrderItem.vue`
- [ ] Adicionar rota em `integrations.routes.js`
- [ ] Adicionar traduções em `locale/en/integrations.json`
- [ ] Adicionar traduções em `locale/en/conversation.json`
- [ ] Testar UI de conexão
- [ ] Testar exibição de pedidos

### Mercado Livre Developer Portal
- [ ] Criar aplicativo em https://developers.mercadolivre.com.br/
- [ ] Configurar Redirect URI: `http://localhost:3000/mercado_livre/callback`
- [ ] Obter Client ID e Client Secret
- [ ] Configurar scopes: `read`, `offline_access`

---

## 🔐 Notas de Segurança

1. **Access Token**: Armazenado criptografado no `Integrations::Hook`
2. **Refresh Token**: Armazenado em `settings` (também criptografado)
3. **Token Expiration**: Tokens do ML expiram em 6 horas - implementar refresh automático
4. **State Parameter**: JWT com account_id para prevenir CSRF
5. **Client Secret**: Nunca expor no frontend, apenas backend

---

## 🚀 Próximos Passos

1. **Criar app no Mercado Livre**: https://developers.mercadolivre.com.br/
2. **Implementar backend** seguindo os passos acima
3. **Implementar frontend** com componentes Vue 3
4. **Testar localmente** com credenciais de teste
5. **Adicionar testes** (RSpec para backend, Jest para frontend)
6. **Implementar webhooks** (opcional) para notificações em tempo real
7. **Documentar** para usuários finais

---

## 📖 Recursos Adicionais

- [Mercado Livre API Docs](https://developers.mercadolivre.com.br/pt_br/api-docs-pt-br)
- [Mercado Livre OAuth Guide](https://developers.mercadolivre.com.br/pt_br/autenticacao-e-autorizacao)
- [Mercado Livre Orders API](https://developers.mercadolivre.com.br/pt_br/orders)
- [Shopify OAuth Reference (para comparação)](https://shopify.dev/docs/apps/auth/oauth)

---

**Dúvidas? Consulte a documentação ou peça ajuda!** 🎯
