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
