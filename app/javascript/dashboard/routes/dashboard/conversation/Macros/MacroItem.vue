<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import { CONVERSATION_EVENTS } from '../../../../helper/AnalyticsHelper/events';
import { useTrack } from 'dashboard/composables';

import NextButton from 'dashboard/components-next/button/Button.vue';
import MacroPreview from './MacroPreview.vue';

const props = defineProps({
  macro: {
    type: Object,
    required: true,
  },
  conversationId: {
    type: [Number, String],
    required: true,
  },
  isReorderMode: {
    type: Boolean,
    default: false,
  },
});

const store = useStore();
const { t } = useI18n();

const isExecuting = ref(false);
const showPreview = ref(false);
const confirmDialog = ref(null);

const confirmDescription = computed(
  () => `${t('MACROS.EXECUTE.CONFIRM.MESSAGE')} "${props.macro.name}"?`
);

const onExecuteClick = async () => {
  const confirmed = await confirmDialog.value.showConfirmation();
  if (confirmed) {
    executeMacro();
  }
};

const executeMacro = async () => {
  try {
    isExecuting.value = true;
    await store.dispatch('macros/execute', {
      macroId: props.macro.id,
      conversationIds: [props.conversationId],
    });
    useTrack(CONVERSATION_EVENTS.EXECUTED_A_MACRO);
    useAlert(t('MACROS.EXECUTE.EXECUTED_SUCCESSFULLY'));
  } catch (error) {
    useAlert(t('MACROS.ERROR'));
  } finally {
    isExecuting.value = false;
  }
};

const toggleMacroPreview = () => {
  showPreview.value = !showPreview.value;
};

const closeMacroPreview = () => {
  showPreview.value = false;
};
</script>

<template>
  <div
    class="relative flex items-center justify-between leading-4 rounded-md h-10 pl-3 pr-2"
    :class="{
      'drag-handle cursor-grab': isReorderMode && !showPreview,
      'cursor-default': showPreview || !isReorderMode,
    }"
  >
    <span
      class="overflow-hidden whitespace-nowrap text-ellipsis font-medium text-n-slate-12"
    >
      {{ macro.name }}
    </span>
    <div class="flex items-center gap-1 justify-end">
      <NextButton
        v-tooltip.left-start="$t('MACROS.EXECUTE.PREVIEW')"
        icon="i-lucide-info"
        slate
        faded
        xs
        @click="toggleMacroPreview"
      />
      <NextButton
        v-tooltip.left-start="$t('MACROS.EXECUTE.BUTTON_TOOLTIP')"
        icon="i-lucide-play"
        slate
        faded
        xs
        :is-loading="isExecuting"
        @click="onExecuteClick"
      />
    </div>
    <transition name="menu-slide">
      <MacroPreview
        v-if="showPreview"
        v-on-clickaway="closeMacroPreview"
        :macro="macro"
      />
    </transition>
    <woot-confirm-modal
      ref="confirmDialog"
      :title="$t('MACROS.EXECUTE.CONFIRM.TITLE')"
      :description="confirmDescription"
      :confirm-label="$t('MACROS.EXECUTE.CONFIRM.YES')"
      :cancel-label="$t('MACROS.EXECUTE.CONFIRM.NO')"
    />
  </div>
</template>
