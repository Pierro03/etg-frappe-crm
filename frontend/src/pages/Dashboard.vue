<template>
  <div class="flex flex-col h-full overflow-hidden">
    <LayoutHeader>
      <template #left-header>
        <ViewBreadcrumbs routeName="Dashboard" />
      </template>
      <template #right-header>
        <Button
          v-if="!editing"
          :label="__('Refresh')"
          :iconLeft="LucideRefreshCcw"
          @click="dashboardItems.reload"
        />
        <Button
          v-if="!editing && isAdmin()"
          :label="__('Edit')"
          :iconLeft="LucidePenLine"
          @click="enableEditing"
        />
        <Button
          v-if="editing"
          :label="__('Chart')"
          iconLeft="lucide-plus"
          @click="showAddChartModal = true"
        />
        <Button
          v-if="editing && isAdmin()"
          :label="__('Reset to Default')"
          :iconLeft="LucideUndo2"
          @click="resetToDefault"
        />
        <Button v-if="editing" :label="__('Cancel')" @click="cancel" />
        <Button
          v-if="editing"
          variant="solid"
          :label="__('Save')"
          :disabled="!dirty"
          :loading="saveDashboard.loading"
          @click="save"
        />
      </template>
    </LayoutHeader>

    <section class="acquisition-command">
      <div class="command-copy">
        <div class="command-kicker">
          <span class="live-pulse" aria-hidden="true"></span>
          {{ __('Live partner acquisition') }}
        </div>
        <h1>{{ __('From travel signal to Sales handoff.') }}</h1>
        <p>
          {{
            __(
              'Research, verify, contact, and qualify every API distribution opportunity in one shared route.',
            )
          }}
        </p>
        <div class="command-actions">
          <a class="route-action" href="/crm/leads/view/list">
            {{ __('Review intelligence') }}
            <LucideArrowUpRight class="size-4" />
          </a>
          <span class="safe-mode">{{ __('Outreach locked · review mode') }}</span>
        </div>
      </div>

      <div class="route-board" aria-label="Partner acquisition route">
        <div class="route-meta">
          <span>{{ __('ETG distribution route') }}</span>
          <span v-if="acquisitionSummary.data">
            {{ acquisitionSummary.data.priority || 0 }} {{ __('priority signals') }}
          </span>
        </div>
        <div class="route-track">
          <div
            v-for="(stage, index) in acquisitionStages"
            :key="stage.key"
            class="route-stage"
          >
            <div class="stage-node" :class="{ active: stage.value > 0 }">
              <span>{{ index + 1 }}</span>
            </div>
            <strong>{{ stage.value }}</strong>
            <span>{{ stage.label }}</span>
          </div>
        </div>
      </div>
    </section>

    <div class="p-5 pb-2 flex items-center gap-4">
      <Dropdown
        v-if="!showDatePicker"
        v-model="preset"
        :options="options"
        class="form-control"
        :placeholder="__('Select Range')"
        :button="{
          label: __(preset),
          class:
            '!w-full justify-start [&>span]:mr-auto [&>svg]:text-ink-gray-5',
          variant: 'outline',
          iconRight: 'lucide-chevron-down',
          iconLeft: 'lucide-calendar',
        }"
      />
      <DateRangePicker
        v-else
        ref="datePickerRef"
        class="!w-48"
        :model-value="filters.period ? parseDateRange(filters.period) : []"
        variant="outline"
        :placeholder="__('Period')"
        :formatter="formatRange"
        @change="
          (v) =>
            updateFilter('period', v, () => {
              showDatePicker = false
              if (!v) {
                filters.period = getLastXDays()
                preset = 'Last 30 Days'
              } else {
                preset = formatter(v)
              }
            })
        "
      >
        <template #prefix>
          <LucideCalendar class="size-4 text-ink-gray-5 mr-2" />
        </template>
      </DateRangePicker>
      <Link
        v-if="isAdmin() || isManager()"
        class="form-control w-48"
        variant="outline"
        :value="filters.user && getUser(filters.user).full_name"
        doctype="User"
        :filters="{
          name: ['in', users.data.crmUsers?.map((u) => u.name)],
          ignore_user_type: 1,
        }"
        :placeholder="__('Sales User')"
        :hideMe="true"
        @change="(v) => updateFilter('user', v)"
      >
        <template #prefix>
          <UserAvatar
            v-if="filters.user"
            class="mr-2"
            :user="filters.user"
            size="sm"
          />
        </template>
        <template #item-prefix="{ option }">
          <UserAvatar class="mr-2" :user="option.value" size="sm" />
        </template>
        <template #item-label="{ option }">
          <Tooltip :text="option.value">
            <div class="cursor-pointer text-ink-gray-9">
              {{ getUser(option.value).full_name }}
            </div>
          </Tooltip>
        </template>
      </Link>
    </div>

    <div class="w-full overflow-y-scroll">
      <DashboardGrid
        v-if="!dashboardItems.loading && dashboardItems.data"
        v-model="dashboardItems.data"
        class="pt-1"
        :editing="editing"
      />
    </div>
  </div>
  <AddChartModal
    v-if="showAddChartModal"
    v-model="showAddChartModal"
    v-model:items="dashboardItems.data"
  />
</template>

<script setup lang="ts">
import AddChartModal from '@/components/Dashboard/AddChartModal.vue'
import LucideRefreshCcw from '~icons/lucide/refresh-ccw'
import LucideUndo2 from '~icons/lucide/undo-2'
import LucidePenLine from '~icons/lucide/pen-line'
import LucideArrowUpRight from '~icons/lucide/arrow-up-right'
import DashboardGrid from '@/components/Dashboard/DashboardGrid.vue'
import UserAvatar from '@/components/UserAvatar.vue'
import ViewBreadcrumbs from '@/components/ViewBreadcrumbs.vue'
import LayoutHeader from '@/components/LayoutHeader.vue'
import Link from '@/components/Controls/Link.vue'
import { usersStore } from '@/stores/users'
import { getSettings } from '@/stores/settings'
import { copy } from '@/utils'
import {
  getLastXDays,
  formatter,
  formatRange,
  parseDateRange,
} from '@/utils/dashboard'
import {
  usePageMeta,
  createResource,
  DateRangePicker,
  Dropdown,
  Tooltip,
} from 'frappe-ui'
import { ref, reactive, computed, provide } from 'vue'

const { users, getUser, isManager, isAdmin } = usersStore()
const { brand } = getSettings()

const acquisitionSummary = createResource({
  url: 'crm.api.dashboard.get_acquisition_summary',
  auto: true,
})

const acquisitionStages = computed(() => [
  {
    key: 'researched',
    label: __('Researched'),
    value: acquisitionSummary.data?.researched || 0,
  },
  {
    key: 'contact_ready',
    label: __('Contact ready'),
    value: acquisitionSummary.data?.contact_ready || 0,
  },
  {
    key: 'contacted',
    label: __('Contacted'),
    value: acquisitionSummary.data?.contacted || 0,
  },
  {
    key: 'qualified',
    label: __('Qualified'),
    value: acquisitionSummary.data?.qualified || 0,
  },
  {
    key: 'handed_off',
    label: __('Sales handoff'),
    value: acquisitionSummary.data?.handed_off || 0,
  },
])

const editing = ref(false)

const showDatePicker = ref(false)
const datePickerRef = ref(null)
const preset = ref('Last 30 Days')
const showAddChartModal = ref(false)

const filters = reactive({
  period: getLastXDays(),
  user: null,
})

const fromDate = computed(() => {
  return parseDateRange(filters.period)[0] || null
})

const toDate = computed(() => {
  return parseDateRange(filters.period)[1] || null
})

function updateFilter(key: string, value: unknown, callback?: () => void) {
  filters[key] = value
  callback?.()
  dashboardItems.reload()
}

const options = computed(() => [
  {
    group: 'Presets',
    hideLabel: true,
    options: [
      {
        label: __('Last 7 Days'),
        onClick: () => {
          preset.value = 'Last 7 Days'
          filters.period = getLastXDays(7)
          dashboardItems.reload()
        },
      },
      {
        label: __('Last 30 Days'),
        onClick: () => {
          preset.value = 'Last 30 Days'
          filters.period = getLastXDays(30)
          dashboardItems.reload()
        },
      },
      {
        label: __('Last 60 Days'),
        onClick: () => {
          preset.value = 'Last 60 Days'
          filters.period = getLastXDays(60)
          dashboardItems.reload()
        },
      },
      {
        label: __('Last 90 Days'),
        onClick: () => {
          preset.value = 'Last 90 Days'
          filters.period = getLastXDays(90)
          dashboardItems.reload()
        },
      },
    ],
  },
  {
    label: __('Custom Range'),
    onClick: () => {
      showDatePicker.value = true
      setTimeout(() => datePickerRef.value?.open(), 0)
      preset.value = 'Custom Range'
      filters.period = null // Reset period to allow custom date selection
    },
  },
])

const dashboardItems = createResource({
  url: 'crm.api.dashboard.get_dashboard',
  makeParams() {
    return {
      from_date: fromDate.value,
      to_date: toDate.value,
      user: filters.user,
    }
  },
  auto: true,
})

const dirty = computed(() => {
  if (!editing.value) return false
  return JSON.stringify(dashboardItems.data) !== JSON.stringify(oldItems.value)
})

const oldItems = ref([])

provide('fromDate', fromDate)
provide('toDate', toDate)
provide('filters', filters)

function enableEditing() {
  editing.value = true
  oldItems.value = copy(dashboardItems.data)
}

function cancel() {
  editing.value = false
  dashboardItems.data = copy(oldItems.value)
}

const saveDashboard = createResource({
  url: 'frappe.client.set_value',
  method: 'POST',
  onSuccess: () => {
    dashboardItems.reload()
    editing.value = false
  },
})

function save() {
  const dashboardItemsCopy = copy(dashboardItems.data)

  dashboardItemsCopy.forEach((item: Record<string, unknown>) => {
    delete item.data
  })

  saveDashboard.submit({
    doctype: 'CRM Dashboard',
    name: 'Manager Dashboard',
    fieldname: 'layout',
    value: JSON.stringify(dashboardItemsCopy),
  })
}

function resetToDefault() {
  createResource({
    url: 'crm.api.dashboard.reset_to_default',
    auto: true,
    onSuccess: () => {
      dashboardItems.reload()
      editing.value = false
    },
  })
}

usePageMeta(() => {
  return { title: __('CRM Dashboard'), icon: brand.favicon }
})
</script>

<style scoped>
.acquisition-command {
  --etg-ink: #0f1714;
  --etg-green: #006b4f;
  --etg-mint: #40be96;
  margin: 20px 20px 4px;
  display: grid;
  grid-template-columns: minmax(280px, 0.9fr) minmax(520px, 1.6fr);
  gap: 32px;
  overflow: hidden;
  border: 1px solid #d9e5df;
  border-radius: 18px;
  background:
    radial-gradient(circle at 8% 8%, rgb(64 190 150 / 16%), transparent 28%),
    linear-gradient(135deg, #f8fbf9 0%, #eef6f2 100%);
  padding: 28px;
  color: var(--etg-ink);
}

.command-kicker,
.route-meta {
  display: flex;
  align-items: center;
  gap: 8px;
  color: #527066;
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.12em;
  text-transform: uppercase;
}

.live-pulse {
  width: 8px;
  height: 8px;
  border-radius: 999px;
  background: var(--etg-mint);
  box-shadow: 0 0 0 5px rgb(64 190 150 / 15%);
}

.command-copy h1 {
  max-width: 560px;
  margin: 18px 0 10px;
  font-size: clamp(26px, 3vw, 40px);
  font-weight: 650;
  letter-spacing: -0.045em;
  line-height: 1.02;
}

.command-copy p {
  max-width: 530px;
  color: #52615c;
  font-size: 14px;
  line-height: 1.55;
}

.command-actions {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 14px;
  margin-top: 22px;
}

.route-action {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  border-radius: 10px;
  background: var(--etg-green);
  padding: 9px 13px;
  color: white;
  font-size: 13px;
  font-weight: 600;
}

.route-action:hover {
  background: #00533e;
  color: white;
}

.route-action:focus-visible {
  outline: 3px solid rgb(64 190 150 / 45%);
  outline-offset: 2px;
}

.safe-mode {
  color: #7b5a10;
  font-size: 12px;
  font-weight: 600;
}

.route-board {
  align-self: stretch;
  border: 1px solid rgb(0 107 79 / 14%);
  border-radius: 14px;
  background: rgb(255 255 255 / 82%);
  padding: 18px 20px 22px;
  box-shadow: 0 18px 50px rgb(20 70 54 / 8%);
}

.route-meta {
  justify-content: space-between;
}

.route-track {
  position: relative;
  display: grid;
  grid-template-columns: repeat(5, minmax(74px, 1fr));
  gap: 8px;
  margin-top: 36px;
}

.route-track::before {
  position: absolute;
  top: 14px;
  right: 9%;
  left: 9%;
  height: 2px;
  background: linear-gradient(90deg, var(--etg-green), #bdd8ce 28%, #dce8e3);
  content: '';
}

.route-stage {
  position: relative;
  z-index: 1;
  display: flex;
  min-width: 0;
  flex-direction: column;
  align-items: center;
  text-align: center;
}

.stage-node {
  display: grid;
  width: 30px;
  height: 30px;
  place-items: center;
  border: 2px solid #cbded6;
  border-radius: 999px;
  background: white;
  color: #739187;
  font-size: 10px;
  font-weight: 700;
}

.stage-node.active {
  border-color: var(--etg-green);
  background: var(--etg-green);
  color: white;
  box-shadow: 0 0 0 6px rgb(0 107 79 / 10%);
}

.route-stage strong {
  margin-top: 18px;
  color: var(--etg-ink);
  font-size: 24px;
  font-variant-numeric: tabular-nums;
  letter-spacing: -0.035em;
}

.route-stage > span:last-child {
  margin-top: 3px;
  color: #64766f;
  font-size: 11px;
  line-height: 1.25;
}

@media (max-width: 1000px) {
  .acquisition-command {
    grid-template-columns: 1fr;
  }
}

@media (max-width: 640px) {
  .acquisition-command {
    margin: 12px;
    padding: 20px;
  }

  .route-board {
    overflow-x: auto;
  }

  .route-track {
    min-width: 560px;
  }
}

@media (prefers-reduced-motion: no-preference) {
  .live-pulse {
    animation: route-pulse 2.4s ease-out infinite;
  }
}

@keyframes route-pulse {
  0%,
  100% {
    box-shadow: 0 0 0 4px rgb(64 190 150 / 14%);
  }
  50% {
    box-shadow: 0 0 0 9px rgb(64 190 150 / 4%);
  }
}
</style>
