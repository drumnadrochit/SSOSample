import { useState } from 'react'
import './App.css'

const delegatedIdentityOptions = [
  {
    value: 'userPrincipalName',
    label: 'User Principal Name',
    example: 'joe@contoso.com',
  },
  {
    value: 'alternateUserPrincipalName',
    label: 'Alternate User Principal Name',
    example: 'joed@contoso.local',
  },
  {
    value: 'usernameFromUserPrincipalName',
    label: 'Username Part of User Principal Name',
    example: 'joe',
  },
  {
    value: 'usernameFromAlternateUserPrincipalName',
    label: 'Username Part of Alternate UPN',
    example: 'joed',
  },
  {
    value: 'samAccountName',
    label: 'On-premises SAM Account Name',
    example: 'CONTOSO\\joe',
  },
]

const presets = {
  multipleDomains: {
    name: 'Multiple internal domains',
    note: 'Cloud sign-in stays on one domain while users exist in separate internal domains.',
    values: {
      cloudUpn: 'joe@contoso.com',
      alternateUpn: 'joe@us.contoso.com',
      onPremSam: 'CONTOSO\\joe',
      connectorDomain: 'us.contoso.com',
      userAccountDomain: 'us.contoso.com',
      internalSpn: 'http/intranet.us.contoso.com',
      delegatedIdentity: 'alternateUserPrincipalName',
      mailAsPrimaryIdentity: true,
      hasDuplicateAcrossForests: false,
      splitPublishingConfigured: false,
    },
  },
  nonRoutable: {
    name: 'Nonroutable internal domain',
    note: 'Internal domain differs from the routable cloud domain used for sign-in.',
    values: {
      cloudUpn: 'joe@contoso.com',
      alternateUpn: 'joe@contoso.usa',
      onPremSam: 'HQ\\joe',
      connectorDomain: 'contoso.usa',
      userAccountDomain: 'contoso.usa',
      internalSpn: 'http/portal.contoso.usa',
      delegatedIdentity: 'alternateUserPrincipalName',
      mailAsPrimaryIdentity: true,
      hasDuplicateAcrossForests: false,
      splitPublishingConfigured: false,
    },
  },
  samCollision: {
    name: 'SAM collision across forests',
    note: 'Short names collide unless you publish twice with different connector groups.',
    values: {
      cloudUpn: 'joe-johns@contoso.com',
      alternateUpn: 'joej@emea.corp.local',
      onPremSam: 'EMEA\\joej',
      connectorDomain: 'na.corp.local',
      userAccountDomain: 'emea.corp.local',
      internalSpn: 'http/sharepoint.corp.local',
      delegatedIdentity: 'samAccountName',
      mailAsPrimaryIdentity: false,
      hasDuplicateAcrossForests: true,
      splitPublishingConfigured: false,
    },
  },
  noDomainName: {
    name: 'No internal domain name',
    note: 'Backend apps may only understand a bare username even when cloud identity is email-based.',
    values: {
      cloudUpn: 'joe@contoso.com',
      alternateUpn: 'joe',
      onPremSam: 'JOE',
      connectorDomain: 'corp.local',
      userAccountDomain: 'corp.local',
      internalSpn: 'http/legacyapp.corp.local',
      delegatedIdentity: 'usernameFromUserPrincipalName',
      mailAsPrimaryIdentity: true,
      hasDuplicateAcrossForests: false,
      splitPublishingConfigured: false,
    },
  },
}

const initialState = presets.multipleDomains.values

function getUsername(identity) {
  return identity.includes('@') ? identity.split('@')[0] : identity
}

function App() {
  const [form, setForm] = useState(initialState)
  const [activePreset, setActivePreset] = useState('multipleDomains')

  const identityValueMap = {
    userPrincipalName: form.cloudUpn,
    alternateUserPrincipalName: form.alternateUpn,
    usernameFromUserPrincipalName: getUsername(form.cloudUpn),
    usernameFromAlternateUserPrincipalName: getUsername(form.alternateUpn),
    samAccountName: form.onPremSam,
  }

  const selectedIdentity = identityValueMap[form.delegatedIdentity]
  const usesSamIdentity = form.delegatedIdentity === 'samAccountName'
  const usesAlternateIdentity = form.delegatedIdentity.includes('alternate')
  const samConnectorMismatch =
    usesSamIdentity && form.connectorDomain !== form.userAccountDomain
  const missingAlternateIdentity = usesAlternateIdentity && !form.alternateUpn.trim()
  const uniquenessRisk =
    form.hasDuplicateAcrossForests && !form.splitPublishingConfigured
  const summaryTone = samConnectorMismatch || missingAlternateIdentity ? 'critical' : uniquenessRisk ? 'warning' : 'good'

  const checks = [
    {
      title: 'Resolved delegated identity',
      tone: selectedIdentity ? 'good' : 'warning',
      detail: selectedIdentity || 'No value can be produced from the selected mapping.',
    },
    {
      title: 'Connector placement rule',
      tone: samConnectorMismatch ? 'critical' : 'good',
      detail: usesSamIdentity
        ? samConnectorMismatch
          ? 'SAM account name requires the connector computer to be joined to the domain that holds the user account.'
          : 'Connector placement matches the domain requirement for SAM-based delegation.'
        : 'This mapping does not require the SAM-specific connector-domain constraint.',
    },
    {
      title: 'Cross-domain uniqueness',
      tone: uniquenessRisk ? 'warning' : 'good',
      detail: uniquenessRisk
        ? 'The delegated sign-in identity may collide across domains or forests. Publish the app twice and isolate audiences with different connector groups.'
        : 'No unresolved delegated-identity collision is simulated.',
    },
    {
      title: 'Microsoft Entra Connect primary sign-in',
      tone: form.mailAsPrimaryIdentity ? 'good' : 'warning',
      detail: form.mailAsPrimaryIdentity
        ? 'The cloud sign-in identity is modeled as the primary email address, matching the documented alternate-ID setup.'
        : 'Primary cloud sign-in is not modeled as mail, which makes alternate-ID testing more fragile.',
    },
  ]

  const summaryMessage = samConnectorMismatch
    ? 'This scenario should fail until the connector is joined to the domain that owns the user SAM account.'
    : missingAlternateIdentity
      ? 'This scenario cannot delegate because the selected alternate identity is blank.'
      : uniquenessRisk
        ? 'This scenario is ambiguous. Split publishing and connector groups are needed before you can trust the result.'
        : 'This scenario is internally consistent for delegated login identity testing.'

  function handleChange(event) {
    const { name, value, type, checked } = event.target
    setForm((current) => ({
      ...current,
      [name]: type === 'checkbox' ? checked : value,
    }))
  }

  function applyPreset(presetKey) {
    setActivePreset(presetKey)
    setForm(presets[presetKey].values)
  }

  return (
    <main className="app-shell">
      <section className="hero-panel">
        <div className="eyebrow">Microsoft Entra Application Proxy</div>
        <h1>KCD Delegated Identity Test Bench</h1>
        <p className="hero-copy">
          Model the exact identity-mapping edge cases from the Microsoft guidance for
          cloud and on-premises identity mismatches. The panel resolves the delegated
          login identity your connector would present and highlights configuration
          mistakes before you touch the real app.
        </p>
        <div className="hero-meta">
          <span>Internal SPN: {form.internalSpn}</span>
          <span>Connector domain: {form.connectorDomain}</span>
          <span>User account domain: {form.userAccountDomain}</span>
        </div>
      </section>

      <section className="preset-panel">
        <div>
          <p className="section-label">Scenario presets</p>
          <h2>Seed the test harness with known identity patterns</h2>
        </div>
        <div className="preset-grid">
          {Object.entries(presets).map(([key, preset]) => (
            <button
              key={key}
              type="button"
              className={key === activePreset ? 'preset active' : 'preset'}
              onClick={() => applyPreset(key)}
            >
              <strong>{preset.name}</strong>
              <span>{preset.note}</span>
            </button>
          ))}
        </div>
      </section>

      <section className="workspace-grid">
        <form className="config-card" onSubmit={(event) => event.preventDefault()}>
          <div className="card-header">
            <p className="section-label">Application config</p>
            <h2>Identity sources and mapping</h2>
          </div>

          <div className="field-grid">
            <label>
              <span>Cloud UPN</span>
              <input name="cloudUpn" value={form.cloudUpn} onChange={handleChange} />
            </label>

            <label>
              <span>Alternate UPN</span>
              <input
                name="alternateUpn"
                value={form.alternateUpn}
                onChange={handleChange}
              />
            </label>

            <label>
              <span>On-premises SAM account name</span>
              <input name="onPremSam" value={form.onPremSam} onChange={handleChange} />
            </label>

            <label>
              <span>Internal application SPN</span>
              <input
                name="internalSpn"
                value={form.internalSpn}
                onChange={handleChange}
              />
            </label>

            <label>
              <span>Connector domain</span>
              <input
                name="connectorDomain"
                value={form.connectorDomain}
                onChange={handleChange}
              />
            </label>

            <label>
              <span>User account domain</span>
              <input
                name="userAccountDomain"
                value={form.userAccountDomain}
                onChange={handleChange}
              />
            </label>
          </div>

          <label className="select-field">
            <span>Delegated login identity</span>
            <select
              name="delegatedIdentity"
              value={form.delegatedIdentity}
              onChange={handleChange}
            >
              {delegatedIdentityOptions.map((option) => (
                <option key={option.value} value={option.value}>
                  {option.label}
                </option>
              ))}
            </select>
          </label>

          <div className="option-grid">
            <label className="toggle">
              <input
                type="checkbox"
                name="mailAsPrimaryIdentity"
                checked={form.mailAsPrimaryIdentity}
                onChange={handleChange}
              />
              <span>Entra Connect models mail as the primary cloud sign-in identity</span>
            </label>

            <label className="toggle">
              <input
                type="checkbox"
                name="hasDuplicateAcrossForests"
                checked={form.hasDuplicateAcrossForests}
                onChange={handleChange}
              />
              <span>Delegated identity is duplicated across domains or forests</span>
            </label>

            <label className="toggle">
              <input
                type="checkbox"
                name="splitPublishingConfigured"
                checked={form.splitPublishingConfigured}
                onChange={handleChange}
              />
              <span>App is published twice with different connector groups and audiences</span>
            </label>
          </div>
        </form>

        <section className="results-card">
          <div className="card-header">
            <p className="section-label">Evaluation</p>
            <h2>Connector-side outcome</h2>
          </div>

          <div className={`summary summary-${summaryTone}`}>
            <span className="summary-label">Current verdict</span>
            <p>{summaryMessage}</p>
          </div>

          <div className="identity-output">
            <div>
              <span className="output-label">Selected mapping</span>
              <strong>
                {
                  delegatedIdentityOptions.find(
                    (option) => option.value === form.delegatedIdentity,
                  )?.label
                }
              </strong>
            </div>
            <div>
              <span className="output-label">Kerberos delegation input</span>
              <code>{selectedIdentity || 'unresolved'}</code>
            </div>
          </div>

          <div className="checks-list">
            {checks.map((check) => (
              <article key={check.title} className={`check check-${check.tone}`}>
                <div>
                  <h3>{check.title}</h3>
                  <p>{check.detail}</p>
                </div>
              </article>
            ))}
          </div>
        </section>
      </section>

      <section className="notes-grid">
        <article className="note-card">
          <p className="section-label">What this models</p>
          <h2>Rules lifted directly from the guidance</h2>
          <ul>
            <li>Delegated login identity is chosen per published application.</li>
            <li>Alternate IDs depend on Microsoft Entra Connect exposing the right sign-in shape.</li>
            <li>Nonunique delegated identities should be isolated with separate connector groups.</li>
            <li>SAM account name requires the connector computer to live in the user account domain.</li>
          </ul>
        </article>

        <article className="note-card emphasis">
          <p className="section-label">How to use it</p>
          <h2>Turn doc guidance into a repeatable preflight</h2>
          <ol>
            <li>Load the closest preset to your environment.</li>
            <li>Set the delegated login identity to match the Enterprise Application SSO setting.</li>
            <li>Mirror connector placement and any known cross-forest duplication.</li>
            <li>Use the verdict and checks to decide whether the real app configuration is safe to test.</li>
          </ol>
        </article>
      </section>
    </main>
  )
}

export default App
