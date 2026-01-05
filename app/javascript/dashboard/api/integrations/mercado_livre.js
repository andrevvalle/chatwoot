/* global axios */

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
