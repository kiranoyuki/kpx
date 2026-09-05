import { Layout, Menu } from 'antd'
import type { MenuProps } from 'antd'
import { Link, Outlet, useLocation } from 'react-router-dom'

const { Sider, Content } = Layout

const NAV_ITEMS: MenuProps['items'] = [
  { key: '/', label: <Link to="/">Overview</Link> },
  { key: '/settings', label: <Link to="/settings">Settings</Link> },
]

export function AppLayout() {
  const { pathname } = useLocation()

  return (
    <Layout style={{ minHeight: '100vh' }}>
      <Sider breakpoint="lg">
        <div
          style={{
            color: 'rgba(255, 255, 255, 0.85)',
            fontWeight: 600,
            fontSize: 18,
            padding: '16px',
          }}
        >
          KPX
        </div>
        <Menu
          theme="dark"
          mode="inline"
          selectedKeys={[pathname]}
          items={NAV_ITEMS}
        />
      </Sider>
      <Layout>
        <Content style={{ margin: '24px', padding: '24px' }}>
          <Outlet />
        </Content>
      </Layout>
    </Layout>
  )
}
