import { frontendURL } from '../../../../helper/URLHelper';
import {
  ROLES,
  CONVERSATION_PERMISSIONS,
} from 'dashboard/constants/permissions.js';

import SettingsWrapper from '../SettingsWrapper.vue';
import Index from './Index.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/product-catalog'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'product_catalog_index',
          meta: {
            permissions: [...ROLES, ...CONVERSATION_PERMISSIONS],
          },
          component: Index,
        },
      ],
    },
  ],
};
