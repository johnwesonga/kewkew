# TODO features

Features below are product requirements that are intentionally not part of the current implementation slice.

## TODO-VF-3: Show queue progress with animation

**Status** — Nice-to-have; out of scope for the initial release.

**User story** — As a visitor waiting in a queue, I want a subtle animation to show my progress so I can understand that my place is moving as staff serve people ahead of me.

### Scope

- Add a lightweight progress visual to the private ticket page while the ticket is active.
- Reflect persisted queue-position updates; animate only when the visitor's position changes, rather than showing continuous or invented progress.
- Keep the ticket number and text position as the accessible source of truth. The animation supplements them and does not replace status announcements.
- Avoid implying an estimated wait or an exact percentage complete when the total queue length is unknown.
- Stop or change the animation when the ticket is called, being served, completed, cancelled, or marked as a no-show.

### Accessibility and behavior

- Respect the visitor's `prefers-reduced-motion` setting and provide a static visual in that case.
- Do not use color or movement as the only indicator of position or ticket status.
- Keep animation brief and non-distracting, and avoid restarting it on routine page refreshes when the position has not changed.

### Dependencies and decisions

- Depends on VF-7 status polling and reliable position updates on the private ticket page.
- Choose the visual treatment after reviewing the visitor UX mock and test it on small mobile screens.

## TODO-VF-2: Estimated wait

**Status** — Nice-to-have; out of scope for the initial release.

**User story** — As a visitor, I want to see an estimated wait so I can decide how to spend my time while waiting.

### Scope

- Estimate wait using queue position and completed-service duration history.
- Clearly label the result as an estimate and display an unavailable state until there is enough data.
- Keep the estimation policy replaceable as real operating data becomes available.
- Add the estimate to service discovery and the private ticket page only when a trustworthy estimate can be calculated.

### Dependencies and decisions

- Depends on reliable queue position and recorded service durations.
- Decide how much completed-service history is required and how estimates respond to changing queue state.

## TODO-VF-1: Prevent repeat signups from the same browser

**Status** — TODO

**User story** — As a visitor who has already joined a queue in this browser, I want another attempt to take me to my existing ticket so I do not accidentally take another place in line.

### Scope

- Apply the rule to one queue session. A browser can hold one active ticket in a particular queue session.
- Scope the claim to the browser profile that joined. A different browser, device, or private browsing profile is treated as a different visitor and may join separately.
- Keep anonymous queues anonymous. Do not use names, email addresses, phone numbers, IP addresses, or device fingerprinting to identify returning visitors.
- Treat a ticket in `waiting`, `called`, or `serving` state as active. Once it is `completed`, `cancelled`, or `no_show`, allow the same browser to join again if that queue session is still open and has capacity.
- A new queue session permits a new signup, even from a browser that joined a previous session.

### Visitor behavior

- When the visitor opens the join form, the browser receives a persistent, opaque browser credential before submitting. This lets retries use the same browser identity even if the join response is interrupted.
- If the same browser submits another join for the same active queue session, do not create a ticket or advance the ticket number. Show the existing ticket number and a way to reopen its private tracking page.
- The duplicate response must not reveal the visitor's name or any other visitor's information.
- If the browser has no usable credential, allow the join to proceed. Explain in product help that cleared, blocked, or unavailable cookies prevent same-browser duplicate detection.
- Do not block signup to a different queue session based on a claim for another queue or session.

### Suggested implementation

- Generate a high-entropy random browser credential before the join form is submitted. Store only its digest in a server-side claim associated with the queue session and ticket after a successful join.
- Enforce one active claim per `(queue_session_id, browser_credential_digest)` with a database uniqueness constraint. Create the ticket and claim transactionally so simultaneous submissions cannot create two active tickets.
- Set the raw credential in an `HttpOnly`, `SameSite=Lax` cookie, marked `Secure` in production. Do not reuse the ticket tracking token as the browser credential.
- Resolve a repeat signup to the existing ticket using the browser claim and provide a private tracking destination. Keep the claim until the ticket becomes terminal, then release it so the visitor can rejoin if the session is still open.
- Expire stale browser claims when their queue session is closed. Choose a cookie lifetime that covers expected queue-session duration and document the effect of cookie expiration.

### Acceptance criteria

- Given a browser with an active ticket for a queue session, when it submits the join flow again, then no new ticket is created and the existing ticket is shown.
- Given two submissions from the same browser at the same time, then at most one active ticket is created for that browser and queue session.
- Given a different browser or device, then it can join the same queue session independently.
- Given the same browser and a different queue session, then it can join that session independently.
- Given a terminal ticket and an open session, then the browser can join again.
- Given a cleared, blocked, or unavailable cookie, then the visitor can still join; the system does not fall back to invasive fingerprinting.
- The browser credential cannot be used to access tickets outside its associated queue claim, and database records contain only its digest.

### Dependencies and decisions

- Depends on visitor ticket creation and private tracking pages (VF-4, VF-5, and VF-6).
- Choose the cookie lifetime and claim cleanup policy before implementation.
- Define the private tracking destination behavior for a repeat attempt when the visitor no longer has their original tracking URL.
