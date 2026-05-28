# Primer: Applying IDS/IPS on Aruba EdgeConnect EC-S-P WAN Interfaces

## Executive Summary

For HPE Aruba Networking EdgeConnect, the best design is not to think of
IDS/IPS as a feature that is simply switched on per physical WAN interface.
Think of it as a policy-driven inspection service:

1. Put interfaces into meaningful firewall zones.
2. Write zone-based firewall policies that identify the traffic to inspect.
3. Set the matching policy action to `Inspect`.
4. Enable IDS/IPS mode on the EC-S-P appliances.
5. Apply a signature profile and keep signatures current.
6. Export events to syslog or SIEM so detections are operationally useful.

For the demo network, the recommended starting posture is:

- Enable IDS/IPS on all three EC-S-P appliances.
- Use separate zones for internet WAN, private WAN/MPLS if present, LAN/user,
  services, management, and SD-WAN overlay traffic.
- Start with IDS-only or IPS-performant for observation and tuning.
- Move selected high-risk traffic to IPS-inline only after validating
  performance and false-positive behavior.
- Inspect LAN-to-internet breakout, inbound internet exceptions, and traffic
  crossing trust boundaries.
- Avoid inspecting everything blindly on day one.

## What EdgeConnect Actually Inspects

EdgeConnect IDS/IPS inspection is selected by firewall policy, not just by port.
HPE documents that traffic is specified for inspection using source zone,
destination zone, and detailed match criteria in Firewall Zone Security Policies.
With IDS/IPS enabled, firewall actions mean:

- `allow`: allow traffic and do not inspect it.
- `deny`: deny traffic and do not inspect it.
- `inspect`: allow traffic and inspect it.

No traffic is inspected until policy rules with the `Inspect` action are
configured.

For the EC-S-P WAN interface question, this means the practical design is:

- Assign WAN interfaces to appropriate firewall zones.
- Create policies for traffic entering or leaving those WAN zones.
- Use `Inspect` on flows where IDS/IPS should apply.
- Ensure the EC-S-P appliance processing the flow has IDS/IPS enabled and
  licensed.

## Prerequisites

Validate these before designing policy:

- EC-S-P appliances support IDS/IPS.
- Appliances must have the Advanced Security or DTD license assigned.
- ECOS version must support the desired IDS/IPS mode.
- Orchestrator must have current IDS/IPS signatures available.
- Signature profiles must be selected or created.
- Firewall zones must be assigned to the relevant interfaces.
- Logging must be configured if events need to reach syslog, Splunk, or SIEM.

Version notes from current HPE documentation:

- IDS/IPS features require supported ECOS versions and eligible appliances.
- IDS support is documented for ECOS 9.1.x.x or later on supported appliances.
- IDS/IPS support is documented for ECOS 9.2.x.x or later on supported
  appliances.
- Orchestrator documentation says `IPS-Inline` can be applied only to appliances
  running ECOS 9.4.1.0 or later; earlier appliances ignore that mode.
- Always verify the exact behavior against the deployed Orchestrator and ECOS
  release because IDS/IPS mode naming and eligibility have changed across
  releases.

## Recommended Zone Model

Use zones to describe trust boundaries, not just cabling.

Suggested starter zones for the demo:

| Zone | Applies To | Default Posture |
| --- | --- | --- |
| `WAN_INTERNET` | Broadband or public internet WAN interfaces | Untrusted |
| `WAN_PRIVATE` | MPLS, private WAN, carrier Ethernet | Semi-trusted |
| `LAN_USER` | User/client VLANs | Trusted but monitored |
| `LAN_SERVICES` | Local servers or demo services | Higher-value internal |
| `MGMT` | Orchestrator/admin/OOB management | Restricted |
| `OVERLAY` | SD-WAN tunnel/overlay-facing policy context | Controlled |

Keep internet and private WAN in separate zones. They have different risk
profiles and usually need different policies.

## Where To Apply IDS/IPS

### 1. Internet Breakout

For local internet breakout from a branch:

- Source zone: `LAN_USER` or `LAN_SERVICES`
- Destination zone: `WAN_INTERNET`
- Action: `Inspect`
- Starting mode: `IPS-Performant`

Why:

- This is the highest-volume and highest-exposure WAN path.
- IPS-performant gives protection while reducing performance risk.
- Inline can be tested later for selected applications or smaller traffic sets.

Recommended match scope:

- Start with web, DNS, common SaaS, and unknown outbound traffic.
- Exclude trusted update repositories or latency-sensitive flows only after
  measuring events and impact.
- Keep explicit denies for traffic that should never leave the branch.

### 2. Inbound Internet Exceptions

For any inbound service exposed through the EC-S-P:

- Source zone: `WAN_INTERNET`
- Destination zone: `LAN_SERVICES` or a dedicated DMZ zone
- Action: `Inspect`
- Starting mode: `IPS-Inline` where supported and performance allows

Why:

- Inbound exceptions are high risk.
- The policy should already be narrow; inline prevention is more appropriate
  for tightly scoped inbound flows than for broad internet breakout.

Design rule:

- Do not allow broad inbound internet access and rely on IDS/IPS to save it.
  Keep the firewall rule narrow first, then inspect the allowed flow.

### 3. Private WAN/MPLS

For private WAN links:

- Source/destination zones depend on the design, commonly `LAN_*` to
  `WAN_PRIVATE` or remote site zones.
- Action: `Inspect` for traffic crossing trust boundaries.
- Starting mode: `IDS Only` or `IPS-Performant`.

Why:

- Private WAN is not automatically safe.
- Inspection is useful for malware movement, scanning, and compromised-host
  behavior.
- False-positive tuning is usually easier if the first phase is detection or
  performant prevention.

### 4. Branch-to-Branch Overlay Traffic

For traffic from one branch LAN zone to another branch LAN or services zone:

- Use zone-based firewall policy between the source and destination zones.
- Set action to `Inspect` for traffic that crosses security boundaries.
- Make sure the appliance that will process the policy has IDS/IPS enabled.

Important behavior:

- With end-to-end segmentation, EdgeConnect typically performs policy and
  IDS/IPS inspection at the source gateway when the destination zone is known.
- If the source gateway cannot determine the destination zone, policy and
  IDS/IPS processing may occur at the destination gateway.
- If you want inspection centralized at a specific EdgeConnect, route and zone
  advertisement behavior must be designed deliberately.

For the demo, prefer a simple model:

- Enable IDS/IPS on all three EC-S-P appliances.
- Use consistent zones and policies across sites.
- Avoid centralized-inspection tricks until the basic policy model is validated.

### 5. Management And Orchestrator Access

For management access:

- Keep management/OOB access in a dedicated `MGMT` zone.
- Default-deny management from WAN zones.
- Allow only jump hosts or admin networks.
- Inspect management flows if they cross an untrusted or semi-trusted boundary.

Do not expose Orchestrator admin/API access broadly on the internet-facing WAN.

## Choosing IDS Only, IPS-Performant, Or IPS-Inline

| Mode | Use When | Tradeoff |
| --- | --- | --- |
| IDS Only | First observation phase, sensitive networks, false-positive learning | Detects and logs but does not block |
| IPS-Performant | General branch internet breakout and higher-throughput WAN traffic | Lower performance impact; initial packets may pass before later packets are dropped |
| IPS-Inline | Narrow high-risk flows, inbound exceptions, mature tuned policy | Strongest enforcement; greatest need for capacity and false-positive validation |

Recommended rollout:

1. Enable IDS/IPS visibility and logging.
2. Run IDS-only or IPS-performant on broad WAN flows.
3. Review events, drops, and application impact.
4. Tune signature profile exceptions where justified.
5. Move selected policies to inline prevention.
6. Keep monitoring drops, throughput, latency, and CPU.

## Signature Profile Strategy

Start with the default signature profile unless there is a clear reason to tune.
Create custom signature profiles only when the default behavior causes known
false positives or when a business-critical flow needs a specific action.

Operational rules:

- Use custom profiles to change rule actions in a controlled way.
- Record every allow-list or action override with a reason, owner, and review
  date.
- Do not use signature overrides as a substitute for correct firewall policy.
- Review signature history before activating updates in sensitive environments.

## Logging And Monitoring

IDS/IPS is only useful if events are reviewed.

Minimum monitoring:

- Orchestrator IDS/IPS status per appliance.
- IDS/IPS mode and signature version.
- Threat/event count.
- Flow drops.
- Packets or bits per second sent to IDS/IPS.
- CPU and throughput after enabling inspection.

Recommended external logging:

- Configure remote log receivers for IDS/IPS events.
- Send logs to syslog, Splunk, or another SIEM.
- Use TCP or TLS transport where supported and appropriate.
- Build alerts for high-severity detections, repeated drops, and sudden event
  spikes.

## EC-S-P WAN Interface Design Pattern

For each EC-S-P appliance:

1. Inventory WAN interfaces.
2. Assign each WAN interface to a correct firewall zone.
3. Confirm interface labels and route labels match the intended WAN service.
4. Confirm local internet breakout design, if used.
5. Configure firewall zone policies:
   - `LAN_USER` to `WAN_INTERNET`: `Inspect`
   - `LAN_SERVICES` to `WAN_INTERNET`: `Inspect`
   - `WAN_INTERNET` to `LAN_SERVICES`: `Inspect` only for explicit allowed
     inbound services
   - `WAN_INTERNET` to `MGMT`: `Deny`
   - `WAN_PRIVATE` to internal zones: `Inspect` where trust boundaries exist
6. Enable IDS/IPS mode on the appliance.
7. Apply the selected signature profile.
8. Validate logs, counters, and application behavior.

## Demo Policy Matrix

Starter matrix for the one-Orchestrator, three-EC-S-P demo:

| Source Zone | Destination Zone | Default Action | IDS/IPS Recommendation |
| --- | --- | --- | --- |
| `LAN_USER` | `WAN_INTERNET` | Inspect | IPS-Performant after IDS observation |
| `LAN_SERVICES` | `WAN_INTERNET` | Inspect | IPS-Performant |
| `WAN_INTERNET` | `LAN_SERVICES` | Deny by default; inspect narrow exceptions | IPS-Inline for approved inbound flows |
| `WAN_INTERNET` | `LAN_USER` | Deny | No inspection needed on denied traffic |
| `WAN_INTERNET` | `MGMT` | Deny | No internet management exposure |
| `LAN_USER` | `LAN_SERVICES` | Inspect or allow by app need | IDS or IPS-Performant |
| `WAN_PRIVATE` | `LAN_SERVICES` | Inspect where required | IDS or IPS-Performant |
| `MGMT` | Appliance/Orchestrator management | Allow from admin sources only | Inspect if crossing untrusted transport |

## Validation Checklist

Before enabling prevention:

- Advanced Security or DTD license is present on each EC-S-P.
- ECOS version supports the selected mode.
- Orchestrator shows the appliances as eligible for IDS/IPS.
- Signature version is current or intentionally pinned.
- Firewall zones are applied to WAN and LAN interfaces.
- At least one `Inspect` policy exists; otherwise nothing will be inspected.
- Remote logging is configured and receiving events.
- Baseline throughput, latency, CPU, and memory are recorded.

After enabling:

- Confirm IDS/IPS mode per appliance.
- Confirm signature profile per appliance.
- Generate or observe benign test traffic that should match the inspected path.
- Verify Orchestrator statistics increment.
- Verify syslog/SIEM receives events.
- Check for unexpected drops.
- Check application experience and tunnel health.
- Record rollback steps.

## Rollback Plan

If IDS/IPS causes a demo-impacting issue:

1. Change affected security policies from `Inspect` to `Allow` for the impacted
   flow, or narrow the match criteria.
2. Move the appliance from `IPS-Inline` to `IPS-Performant` or `IDS Only`.
3. If needed, turn IDS/IPS off for the impacted appliance.
4. Restore the previous signature profile or remove the recent override.
5. Validate that application traffic has recovered.
6. Keep the event evidence for later tuning.

Do not delete the zone model during rollback. Roll back inspection behavior
first; preserve the policy structure so tuning remains understandable.

## Common Mistakes

- Expecting inspection just because IDS/IPS is enabled on the appliance.
- Forgetting that policy action must be `Inspect`.
- Using `Allow All` on a WAN interface because it is behind another firewall,
  then losing visibility into flows that should have been inspected.
- Applying inline IPS broadly before observing false positives.
- Treating private WAN as inherently trusted.
- Enabling prevention without syslog/SIEM visibility.
- Tuning signatures without documenting why.
- Assuming the destination appliance will inspect branch-to-branch traffic when
  the source gateway already determined the destination zone.

## Source References

- HPE Aruba Networking EdgeConnect SD-WAN Orchestrator IDS/IPS documentation:
  https://arubanetworking.hpe.com/techdocs/sdwan/docs/orch/configuration/overlays/ids/
- HPE Aruba Networking EdgeConnect SD-WAN QuickSpecs:
  https://www.hpe.com/us/en/collaterals/collateral.a50004289enw.html
- HPE Aruba Networking EdgeConnect SD-WAN Security Features Guide:
  https://arubanetworking.hpe.com/techdocs/sdwan-PDFs/docs/tips/Security-Guide-9.5-Release-latest.pdf
- Firewall Zones documentation:
  https://arubanetworking.hpe.com/techdocs/sdwan_auto/docs/orch/configuration/overlays/fw-zones/
- Security Policies documentation:
  https://arubanetworking.hpe.com/techdocs/sdwan/docs/orch/configuration/policy/security-policies/
