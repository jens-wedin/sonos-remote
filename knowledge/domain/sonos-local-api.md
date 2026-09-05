# Sonos local API (verified on Jens's S2 system, firmware 96.x)

- Discovery: Bonjour `_sonos._tcp`. TXT keys: `uuid` (RINCON_…), `hhid`, `location` (http://IP:1400/xml/device_description.xml), `sslport` 1443, `wss` /websocket/api, `variant` 2 = S2.
- REST: `https://IP:1443/api/v1/...`, header `X-Sonos-Api-Key: 123e4567-e89b-12d3-a456-426655440000`, self-signed cert, responses use `Connection: Close`.
- Group-scoped calls must go to the group's coordinator. Sent to a member you get 404 `groupCoordinatorChanged` with `GROUP_STATUS_MOVED` + `playerId` of the coordinator, or `GROUP_STATUS_GONE`.
- Missing key → 400 `globalError` `ERROR_API_KEY_VALIDATION_FAILED`. Authentication switched on in the Sonos app → 401 `ERROR_NOT_AUTHORIZED`.
- Websocket: `wss://IP:1443/websocket/api`, subprotocol `v1.api.smartspeaker.audio`, same key header, no Origin. Frames are JSON arrays `[header, body]`. Subscribe: `[{"namespace":"playback:1","command":"subscribe","groupId":"…"},{}]`. Ack has `response:"subscribe"`, `success:true`, `type:"none"`; the current state is pushed right after. Unknown namespace → `type:"globalError"`, `ERROR_UNSUPPORTED_NAMESPACE`.
- The `groups` event body has no `playbackState`; the REST groups response does.
- Favorites events are `versionChanged`; re-fetch the list over REST.
- EQ is not in the 1443 API. UPnP `RenderingControl` on `http://IP:1400/MediaRenderer/RenderingControl/Control`: GetBass/SetBass, GetTreble/SetTreble, GetLoudness/SetLoudness (Channel Master), GetEQ/SetEQ with EQType SubGain, SubCrossover. Unsupported EQType → HTTP 500 SOAP fault errorCode 402.
- Sub detection: `GetEQ SubCrossover` > 0 means a sub is attached (Amp reports 99, others 0).
- A player can stay listed in Bonjour while actually unreachable — the mDNS record is a cached announcement, not a liveness check. REST calls to it then time out (`NSURLErrorDomain -1001`) even though `dns-sd`/`NWBrowser` still shows it. Don't treat "present in Bonjour" as "reachable"; fail over to another discovered player and retry with backoff instead of trusting the first result.
