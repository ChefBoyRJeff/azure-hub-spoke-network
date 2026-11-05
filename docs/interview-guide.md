# Interview Guide: Azure Hub-and-Spoke Network

Talking points for this project. Everything happened in a **personal lab subscription**. Describe it as hands-on lab work, not production experience.

> **Framing line:** "I built a hub-and-spoke network in Bicep while studying for AZ-104, then did the harder, more realistic exercise: I took an environment I'd built by hand in the portal, brought it under code, found what was wrong with it, fixed it through code, and proved the fixes with real traffic."

## 1. Three-to-Five-Minute Walkthrough

**Problem (30 s).** A single flat network gets hard to secure as an organization grows. Hub-and-spoke puts shared services in one hub and isolates workloads in spokes that only connect to the hub. The second problem is one every team has: environments built by hand in the portal drift from standards and can't be rebuilt.

**Lab 1, built from code (60 s).**
- A hub VNet and two spokes, deployed from Bicep. Each spoke comes from one **reusable module**, driven by an array, so adding a spoke is one line.
- Peerings in both directions. The loops run one at a time with `@batchSize(1)`, because Azure can't update two peerings on the same VNet at once.
- **Least-privilege NSGs** that override Azure's default `AllowVnetInBound` rule, and **route tables** that send spoke egress to a future network virtual appliance in the hub.
- Cost guardrails first: a budget, and an Azure Policy that blocks expensive resource types, tested by trying to create a NAT gateway and getting `RequestDisallowedByPolicy`.

**Lab 2, portal to code (2 min).**
- I built a small hub and spoke with two VMs **by hand in the portal**, then exported and decompiled it. The decompile produced **18 errors**, because the export declared subnets and peerings twice. I cleaned it up until what-if showed **0 creates and 0 deletes** against the live environment.
- Then I found **four problems** in the portal build: the same NSG on both the subnet and the NIC, peering names swapped between the two sides, no tags, and NSGs with only default rules, which let **all** traffic in from the peered VNet.
- I fixed each one through code, one at a time: capture before-evidence, edit, what-if, compare with the previous what-if, deploy, verify.
- I proved the result with a **test matrix that includes traffic that should be blocked**. 8 of 8 passed, including TCP 8080 timing out where it used to succeed.

**Close (15 s).** "What I'd highlight: what-if isn't validation. My peering rename looked clean in what-if and still failed at deployment, and I had to prove security fixes with traffic, not just configuration."

## 2. Ten-Minute Deep Dive (Outline)

| Minutes | Topic | Show |
|---|---|---|
| 0–2 | Lab 1 design: address plan, spoke module, peering, NSG rule order, UDRs | README diagram, `modules/spoke.bicep` |
| 2–4 | Portal to code: export, the 18 decompile errors and why, what-if baseline | `lab2-01`, `lab2-02` |
| 4–6 | The four findings and the fix-through-code loop | README findings table, `lab2-03` to `lab2-09` |
| 6–8 | Controlled failure: the peering rename, `AnotherPeeringAlreadyReferencesRemoteVnet`, `Disconnected` state | `lab2-11` to `lab2-15` |
| 8–10 | Proof: effective routes and NSGs, IP flow verify, the 8-test matrix, timeout vs. refused | `lab2-16`, `lab2-21` |

## 3. Likely Questions and Answers

**Q: Why hub-and-spoke instead of one big VNet?**
Isolation and central control. Each workload gets its own spoke, so a problem or a misconfiguration in one doesn't reach the others, and shared services such as a firewall, VPN gateway, or DNS are deployed and paid for once in the hub. The cost is more peerings and routing to manage.

**Q: Can spoke1 talk to spoke2?**
Not by default. **Peering isn't transitive**: both spokes peer with the hub, but not with each other. To connect them, you either peer them directly or route through an appliance in the hub. My route tables send spoke traffic to 10.0.1.4 in the hub for that reason. The appliance itself isn't deployed, to keep the lab at $0.

**Q: Why did you need a deny rule when NSGs already have one?**
Because the default `AllowVnetInBound` rule at priority 65000 allows anything in the `VirtualNetwork` service tag, and that tag **includes peered VNets**. The default deny at 65500 never gets reached for that traffic. So I added my own `Deny-VNet-Inbound` at priority 4000 and allowed only what each workload needs above it. In Lab 2, the portal-built NSGs had only the defaults, which is why TCP 8080 from the hub got through.

**Q: What was wrong with the exported template?**
The export declared subnets and peerings twice: inline inside each VNet and again as separate child resources. The two copies referenced each other, which caused circular-dependency and self-reference errors, and everything pointing at them failed too: 18 errors. I kept subnets inline, kept peerings as child resources, and built the NIC subnet IDs from the VNet. Then I didn't trust it until what-if showed zero creates and zero deletes against the real environment.

**Q: Walk me through the peering rename failure.**
You can't rename an Azure resource, so renaming means delete and recreate. Bicep in incremental mode never deletes, so changing the names in code tries to **add** two new peerings next to the old ones. What-if showed two clean creates and no warning. I deployed anyway, on purpose, and it failed with `AnotherPeeringAlreadyReferencesRemoteVnet`, because a VNet can't have two peerings to the same remote VNet. The old peerings were still connected afterward, so nothing broke. When I deleted the hub side first, the spoke side immediately showed `Disconnected`. Then I deleted the spoke side and redeployed with the correct names. Lesson: what-if predicts property changes; it doesn't check service rules.

**Q: How did you prove the NSG changes worked?**
With traffic, including negative tests. My script runs ping and TCP tests through Run Command, so there are no public IPs, and Network Watcher IP flow verify names the exact rule that allows or denies each flow. Every test has an expected result. A blocked test passes **only on a timeout**: an NSG silently drops the packet, while "connection refused" means the packet reached the VM and nothing was listening. Counting both as blocked would hide a broken rule.

**Q: What does the route table tell you?**
Two things I saw in the effective routes. **Longest prefix match:** the platform installs a `10.0.0.0/8` drop route, but the more specific `/16` peering route wins, so the traffic flows. And **a route isn't a path:** `0.0.0.0/0 → Internet` is listed, but with default outbound access off and no public IP or NAT gateway, the VMs still have no internet access.

**Q: Did anything surprise you?**
The raw effective-rules JSON showed a second security layer I didn't create: an Azure Virtual Network Manager **security admin rule**. Admin rules are evaluated before NSGs and can't be overridden by them. It only blocked some outbound IPv6, so it didn't affect my tests, but it's a real place to look when an NSG looks right and traffic is still blocked.

**Q: What went wrong operationally?**
An interrupted test run left a VM running. My script deallocates both VMs in a `finally` block, but I pressed Ctrl+C while `az vm start` was in flight. The start had already reached Azure, and the cleanup itself got interrupted. A power-state check caught it, and I deallocated by hand. Lesson: a safety mechanism should be verified, and it shouldn't be the only one. Auto-shutdown would be the second guard.

**Q: How do you keep this cheap?**
Guardrails before deploying: a budget with alerts, and a Deny policy for expensive resource types, which I tested. VNets, NSGs, route tables, and idle peering are free. The VMs stayed deallocated except during tests, so the only charge was two OS disks, about $5 a month, until I tore Lab 2 down.

**Q: What would you change for production?**
Deploy a real inspection point in the hub (Azure Firewall or an NVA) so the routes actually go somewhere. Enforce tags with Azure Policy. Run what-if on pull requests in a pipeline, which I built in my CI/CD project. Use a parameter file per environment. Add NSG flow logs. And use a deployment stack or complete mode so deletions are part of the reviewed change, not a manual step.

## 4. Follow-Up Challenges to Practice

Answer these out loud, without notes:

1. You add a third spoke. What exactly changes in the code, and what does what-if show?
2. Spoke-to-spoke traffic through the hub NVA fails. Name three things you'd check, in order.
3. Why does the hub's SSH session to the spoke work without an inbound rule on the hub?
4. A teammate says, "What-if was clean, so the deployment is safe." What do you tell them?
5. What's the difference between an NSG on a subnet and an NSG on a NIC, and why was having both a problem here?
6. How would you get Lab 2's portal build to stop drifting in the future?
7. A VM's effective routes show the next hop as `None` for a destination. What does that mean?

### Model answers

Check your own answers against these. Don't memorize them; an answer recited word for word sounds rehearsed.

**1. A third spoke.** One new object in the `spokes` array: a name, a non-overlapping address space, and a workload subnet prefix. What-if shows the new VNet, its NSG, its route table, the spoke-to-hub peering, and a new hub-to-spoke peering, with **no changes** to the existing spokes. That's the point of the module.

**2. Spoke-to-spoke through the NVA fails.** First, **effective routes** on the source NIC: is the next hop the NVA's IP, and is the route active? Second, the **NVA itself**: IP forwarding enabled on its NIC in Azure, **and** forwarding enabled in the guest OS. Both are needed. Third, **NSGs on the path**: the spoke NSGs and the NVA's subnet NSG must allow the forwarded traffic, using IP flow verify to name the rule. Also check that the peerings allow forwarded traffic.

**3. SSH without an inbound rule on the hub.** NSGs are **stateful**. The hub opened the connection, so the return traffic for that session is allowed automatically. A new connection started by the spoke would need an inbound rule, and my test matrix proves it's blocked.

**4. "What-if was clean."** What-if predicts which properties will change; it doesn't check every service rule. My peering rename looked like two clean creates and still failed with `AnotherPeeringAlreadyReferencesRemoteVnet`. A clean what-if is necessary, not sufficient. You still verify after deploying.

**5. Subnet NSG vs. NIC NSG.** A subnet NSG applies to everything in the subnet; a NIC NSG applies to one VM. Inbound traffic is evaluated against the subnet NSG, then the NIC NSG, and both must allow it. Attaching the **same** NSG at both levels adds no security, just duplicate evaluation, and it doubles what you have to read in effective rules and IP flow verify. I removed the NIC association and kept the subnet one.

**6. Stopping drift.** Make code the source of truth: deploy only through Bicep, ideally through a pipeline with what-if on pull requests. Run a scheduled what-if that reports differences. Enforce standards with Azure Policy: required tags, allowed resource types. And limit who has write access in the portal.

**7. Next hop `None`.** Traffic matching that route is **dropped**. In my lab, the platform's `10.0.0.0/8 → None` route would have dropped traffic to the peered VNet if the more specific `/16` peering route weren't there. A route to `None` usually means a missing peering, or a user-defined route that deliberately blackholes traffic.

## 6. Lab 3: Internal Load Balancer and Bastion

### Two-minute walkthrough

"I put two web VMs in a spoke behind an internal Standard Load Balancer and gave admins SSH through Azure Bastion, with no public IPs on any VM. The load balancer came up with both health probes at 0%. Network Watcher can't test the probe address, so I ran a packet capture on the VM: only one probe packet arrived in 20 seconds. The cause was my own Lab 1 rule. My `VirtualNetwork` deny at priority 4000 also matches the probe source, 168.63.129.16, and it's evaluated before Azure's default load balancer allow at 65001. One allow rule for the `AzureLoadBalancer` tag at 3900 fixed it: 37 probe packets in 20 seconds, and 100% health. Then I measured failover by stopping the web service on one VM under load: traffic moved in about 7 seconds, it came back about 6 seconds after the restart, and 6 of 119 requests failed in that window. For Bastion, IP flow verify predicted the SSH block into the spoke before Bastion was even up. I added the rule through code, verified it, and the logins worked. The VM logs show the source as the Bastion subnet. Both NSG fixes went back into the Lab 1 Bicep module."

### Likely questions

**Q: Why did your health probes fail when Azure has a default rule allowing the load balancer?**
Default rules are at 65000 and above, and my custom deny was at 4000. The `VirtualNetwork` service tag includes the host virtual IP `168.63.129.16`, which is where probes come from, so my deny matched first. The fix is an explicit `AzureLoadBalancer` allow above the deny. I proved the cause by experiment: probe packets went from 1 to 37 per 20 seconds after the rule, with nothing else changed.

**Q: How did you troubleshoot without Network Watcher?**
IP flow verify and next hop both refuse the platform address with `IpAddressInRestrictedAddressSpace`. So I went one layer down: confirmed the web server listened on `0.0.0.0:443`, then captured packets on the backend. A listening service plus missing probe packets put the drop outside the VM, which pointed at the NSG.

**Q: The first test sent 20 out of 20 connections to one VM. Is the load balancer broken?**
No. Azure Load Balancer distributes by a hash of the 5-tuple, not round-robin, and that run started right after one backend turned healthy. A 50-connection re-test gave 17/33, and the final run 20/30. I recorded the 20/0 result rather than hiding it, and re-tested with a bigger sample.

**Q: Why did requests from a backend to its own load balancer fail?**
Hairpinning isn't supported on Azure Load Balancer. When a backend's flow hashes back to itself, it fails. I saw 6 failures and 14 successes to the other VM, and 0 to itself.

**Q: What does your failover number depend on?**
Mainly the probe settings: a 5-second interval and a threshold of 1, so the backend is marked down at the first failed probe. Also on when the crash falls inside the probe interval. The failures came only in the window between the crash and the next probe.

**Q: Why Bastion instead of a jump box with a public IP?**
No public IP on any VM, no inbound SSH from the internet, and access goes through Entra sign-in to the portal. The trade-offs are cost, about $0.19 an hour for Basic, and that Basic is portal-only. Also, my subscription's cost policy blocked Bastion, so I used a one-day exemption scoped to the lab resource group and deleted it at teardown.

**Q: Bastion failed twice. What happened?**
The first failure was configuration: in East US, Bastion needed a zone-redundant public IP, and I'd created one with no zone. The second was `BastionDeploymentUnavailable`, a capacity limit in the region, which no configuration change fixes. I checked every prerequisite to rule out my side, kept the subnet and IP, and retried later. It succeeded with the same configuration.

**Q: Tell me about a mistake you made.**
Two from this lab. First, a deploy ran from the wrong version of a file, because my safety check only looked for deletions. Now every run checks each expected line and stops before touching Azure if one is missing. That check caught the next mistake, a file copied before an edit finished. Second, I misread a what-if index and "corrected" my own evidence wrongly. What-if lists subnets by name, not template order. I found it when the line stayed after the fix, and I recorded the retraction rather than deleting the earlier note.

**Q: Everything failed from the client after a deploy. How did you approach it?**
I didn't assume the deploy broke it. I checked the Azure side (subnet, NIC, effective routes, next hop, the NSG rule, and the activity log for any change), then inside the VM, plus a control test from another VM. curl connected over TCP in 2 ms, then failed with a TLS error, from both VMs. That ruled out the network. My test used `https://` against a plain HTTP server.

### Practice challenges (Lab 3)

1. Your probe uses TCP 443 instead of HTTP. What failure would it miss?
2. You need SSH from Bastion to every spoke. Where do you put the rule, and what's its source?
3. Why can't a backend VM reach its own load balancer frontend, and how would you work around it?
4. The load balancer works, but the VMs can't install updates. Why, and what are two fixes?

**Model answers.**
1. A TCP probe only checks that something accepts the connection. A hung or broken application that still holds the port open stays "healthy". An HTTP probe needs a 200 from the path.
2. In each spoke's NSG, which in my code means the shared spoke module, so every spoke gets it. Source: the `AzureBastionSubnet` prefix, TCP 22, above the VirtualNetwork deny.
3. Hairpinning isn't supported. A flow that hashes back to the same backend fails. Call the local service directly, or put the client tier in a different backend.
4. Private subnets and a spoke default route to an appliance that isn't deployed, so there's no outbound path. Fixes: a NAT gateway on the subnet, or a real firewall or appliance at the route's next hop.

### Honest limits (Lab 3)

- Ran for about 3 hours in a lab subscription. It wasn't a production web tier.
- Plain HTTP on 443, not TLS. One test client.
- The load balancer was built in the portal. Its Bicep was what-if checked, not deployed.
- The hub `snet-shared` still has no NSG.

## 5. Honest Limits to Mention If Asked

- It's a lab: two spokes in Lab 1, one hub and one spoke with two VMs in Lab 2.
- No appliance is deployed in the hub, so the UDRs show intent but weren't traffic-tested (Lab 3 confirmed the spoke VMs have no egress because of it). A route break/fix scenario is the next planned exercise.
- Lab 2 was torn down on 2026-11-01. A fresh rebuild from `lab2/main.bicep` is expected to work but hasn't been tested.
- The peering rename needed a manual delete, because incremental mode doesn't delete.
