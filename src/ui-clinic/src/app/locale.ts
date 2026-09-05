import enUS from 'antd/locale/en_US'
import viVN from 'antd/locale/vi_VN'

const LOCALES = { en: enUS, vi: viVN } as const

// English for now. Switching the whole app to Vietnamese later is this one
// line: change `en` to `vi`.
export const activeLocale = LOCALES.en
