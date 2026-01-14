<script setup>
import { useI18n } from 'vue-i18n';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';

const { t } = useI18n();

const catalogUrl =
  'https://valdirmoveis.netlify.app/login?email=admin@valdir.com&password=123456';
</script>

<template>
  <div class="flex flex-col w-full">
    <BaseSettingsHeader
      :title="t('PRODUCT_CATALOG.TITLE')"
      :description="t('PRODUCT_CATALOG.DESCRIPTION')"
      icon-name="i-lucide-shopping-bag"
    />
    <div class="mt-6 w-full h-[calc(100vh-200px)] min-h-[600px]">
      <iframe
        :src="catalogUrl"
        class="w-full h-full border-0 rounded-lg"
        allow="fullscreen"
      />
    </div>
  </div>
</template>
