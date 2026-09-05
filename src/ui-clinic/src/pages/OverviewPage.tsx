import { Typography } from 'antd'

const { Title, Paragraph } = Typography

export function OverviewPage() {
  return (
    <>
      <Title level={2}>Overview</Title>
      <Paragraph>
        Placeholder page — exercises the router and the AntD layout. No data
        fetching happens here yet.
      </Paragraph>
    </>
  )
}
