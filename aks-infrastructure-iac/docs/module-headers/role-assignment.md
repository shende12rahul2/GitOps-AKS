# role-assignment

Creates Azure role assignments from a map with **static keys** (e.g.
`"kubelet-acr-pull"`), so `for_each` is plannable even when principal IDs are
only known after apply. Granting `Owner` or `User Access Administrator` is
rejected by validation; those require an out-of-band, reviewed process.
