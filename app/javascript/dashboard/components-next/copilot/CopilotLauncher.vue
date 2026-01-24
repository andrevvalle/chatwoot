<script setup>
import { computed, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ButtonGroup from 'dashboard/components-next/buttonGroup/ButtonGroup.vue';
import { LocalStorage } from 'shared/helpers/localStorage';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';
import { setColorTheme } from 'dashboard/helper/themeHelper.js';

const route = useRoute();
const { t } = useI18n();

const isConversationRoute = computed(() => {
  const CONVERSATION_ROUTES = [
    'inbox_conversation',
    'conversation_through_inbox',
    'conversations_through_label',
    'team_conversations_through_label',
    'conversations_through_folders',
    'conversation_through_mentions',
    'conversation_through_unattended',
    'conversation_through_participating',
    'inbox_view_conversation',
  ];
  return CONVERSATION_ROUTES.includes(route.name);
});

const showThemeLauncher = computed(() => !isConversationRoute.value);

const currentTheme = ref(
  LocalStorage.get(LOCAL_STORAGE_KEYS.COLOR_SCHEME) || 'auto'
);

const isDarkMode = computed(() => currentTheme.value === 'dark');

const themeIcon = computed(() => isDarkMode.value ? 'i-lucide-sun' : 'i-lucide-moon');

const themeTooltip = computed(() =>
  isDarkMode.value ? t('COMMAND_BAR.COMMANDS.LIGHT_MODE') : t('COMMAND_BAR.COMMANDS.DARK_MODE')
);

const toggleTheme = () => {
  const nextTheme = isDarkMode.value ? 'light' : 'dark';
  currentTheme.value = nextTheme;
  LocalStorage.set(LOCAL_STORAGE_KEYS.COLOR_SCHEME, nextTheme);
  setColorTheme(false);
};
</script>

<template>
  <div
    v-if="showThemeLauncher"
    class="fixed bottom-4 ltr:right-4 rtl:left-4 z-50"
  >
    <ButtonGroup
      class="rounded-full bg-n-alpha-2 backdrop-blur-lg p-1 shadow hover:shadow-md"
    >
      <Button
        v-tooltip.top="themeTooltip"
        :icon="themeIcon"
        no-animation
        class="!rounded-full !bg-n-solid-3 dark:!bg-n-alpha-2 !text-n-slate-12 text-xl transition-all duration-200 ease-out hover:brightness-110"
        lg
        @click="toggleTheme"
      />
    </ButtonGroup>
  </div>
  <template v-else />
</template>
