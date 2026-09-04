import { Typography } from 'antd'

const { Title, Paragraph } = Typography

export function SettingsPage() {
  return (
    <>
      <Title level={2}>Settings</Title>
      <Paragraph>
        Second placeholder page — confirms navigation switches routes rather
        than re-rendering the same screen.
      </Paragraph>
    </>
  )
}
