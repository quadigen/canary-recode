package main

import services "../src/engine/services"
import json "core:encoding/json"
import "core:fmt"

main :: proc() {
    release_sha := "35e150cda4dba6279f7815338be0a4e7d570688b"
    release: services.GitHub_Release
    err := json.unmarshal_string(
        `{"tag_name":"v1.19.4","target_commitish":"35e150cda4dba6279f7815338be0a4e7d570688b","assets":[]}`,
        &release,
    )
    assert(err == nil)
    assert(release.tag_name == "v1.19.4")
    assert(release.target_commitish == release_sha)

    assert(services.Update_Version_Compare("v1.19.4", "1.19.4") == 0)
    assert(services.Update_Version_Compare("v1.19.4", "1.19.0-dev") > 0)
    assert(!services.Update_Release_Is_Newer("1.19.4", "1.19.0-dev", release.target_commitish, release_sha))
    assert(services.Update_Release_Is_Newer("1.19.4", "1.19.0-dev", release_sha, "different-commit"))
    assert(services.Update_Release_Is_Newer("1.19.4", "1.19.0-dev", "master", "master"))
    assert(!services.Update_Release_Is_Newer("1.19.4", "1.19.4", release_sha, "different-commit"))

    fmt.println("UPDATE_VERSION_SMOKE_PASSED")
}
