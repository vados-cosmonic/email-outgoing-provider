set shell := ["zsh", "-uc"]

shebang := if os() == "macos" { "/bin/zsh" } else { "/usr/bin/zsh" }

just := env_var_or_default("JUST", just_executable())
cargo := env_var_or_default("CARGO", "cargo")
wash := env_var_or_default("WASH", "wash")

component_hello_world_path := "examples" / "rust" / "components" / "email-hello-world"
component_hello_world_manifest := component_hello_world_path / "Cargo.toml"
component_hello_world_signed_component := component_hello_world_path / "build" / "email_hello_world_s.wasm"
component_hello_world_id := "email-hello-world"

provider_email_outgoing_path := "."
provider_email_outgoing_par_path := provider_email_outgoing_path / "build" / "email-outgoing-provider.par.gz"
provider_email_outgoing_id := "email-outgoing"

config_name := "hello-world"

default:
    {{just}} --list

###############
# Development #
###############

# Lint
@lint:
    {{cargo}} clippy --all-targets
    {{cargo}} clippy --manifest-path {{component_hello_world_manifest}} --all-targets

# Format
@fmt:
    {{cargo}} fmt
    {{cargo}} fmt --manifest-path {{component_hello_world_manifest}}

# Clean (remove all build artifacts)
clean:
    rm -rf {{component_hello_world_signed_component}}
    rm -rf {{provider_email_outgoing_par_path}}

#########
# Build #
#########

# Build all code
build: build-provider-outgoing-email build-component-hello-world

# Build the capability provider
@build-provider-outgoing-email:
    echo "=> Building outgoing email provider..."
    {{wash}} build

# Build the example component
@build-component-hello-world:
    echo "=> Building email hello world component..."
    {{wash}} build --config-path "examples/rust/components/email-hello-world"

##########
# Deploy #
##########

# TODO: re-enable wadm-by-default once WADM manifest works properly

# # Deploy the demo (powered by WADM)
# deploy-demo: start-local-mail-server start-wasmcloud-host deploy-demo-wadm

# # Undeploy the demo (powered by WADM)
# undeploy-demo: undeploy-demo-wadm stop-wasmcloud-host stop-local-mail-server

# # Redeploy the demo (powered by WADM)
# redeploy: redeploy-demo-wadm

# Deploy the demo
deploy-demo: start-local-mail-server start-wasmcloud-host deploy-demo-imperative

# Undeploy the demo
undeploy-demo: undeploy-demo-imperative stop-wasmcloud-host stop-local-mail-server

# Redeploy the demo
redeploy: redeploy-demo-imperative

# Deploy the demo, imperatively
@deploy-demo-imperative: build
    echo "=> Starting a wasmCloud host in the background using wash up (daemonized)"
    {{wash}} up -d || true
    echo "=> Setting configuration for the provider..."
    {{wash}} config put {{config_name}} OUTGOING_CFG_hello-world_JSON='{"name":"hello-world","smtp":{"url":"smtp://127.0.0.1:1025"}}'
    echo "=> Starting the capability provider..."
    {{wash}} start provider file://{{ absolute_path(provider_email_outgoing_par_path) }} {{provider_email_outgoing_id}}
    echo "=> Starting the hello world component..."
    {{wash}} start component file://{{absolute_path(component_hello_world_signed_component)}} {{component_hello_world_id}}
    echo "=> Linking the provider and component on the 'prototype:email' WIT interface..."
    {{wash}} link put \
    {{component_hello_world_id}} \
    {{provider_email_outgoing_id}} \
    prototype email \
    --target-config {{config_name}} \
    --interface outgoing-sender \
    --interface outgoing-config

# Undeploy the demo, imperatively
@undeploy-demo-imperative:
    echo "=> Deleting link"
    {{wash}} link del \
    {{component_hello_world_id}} \
    --namespace prototype \
    --package email || true
    echo "=> Deleting config"
    {{wash}} link del \
    {{component_hello_world_id}} \
    --namespace prototype \
    --package email
    echo "=> Stopping component"
    {{wash}} stop component {{component_hello_world_id}} || true
    echo "=> Stopping provider"
    {{wash}} stop provider {{provider_email_outgoing_id}} ||  true

# Redeploy the demo, imperatively
redeploy-demo-imperative: undeploy-demo-imperative deploy-demo-imperative

# Deploy the demo with WADM
@deploy-demo-wadm: build undeploy-demo-wadm
    {{wash}} app deploy demo-email-hello-world.wadm.yaml

# Undeploy the demo with WADM
@undeploy-demo-wadm:
    {{wash}} app delete demo-email-hello-world v0.0.1 || true

# Re-deploy the demo with WADM
redeploy-demo-wadm: undeploy-demo-wadm deploy-demo-wadm

# Invoke the demo component with `wash`
send-demo-email:
    {{wash}} call {{component_hello_world_id}} "examples:email-hello-world/invoke.call"

#########
# Infra #
#########

smtp_server_container := "demo-smtp"
smtp_server_image := "dockage/mailcatcher:0.9.0"

# Start a local SMTP server, stopping one if currently present
@start-local-mail-server:
    echo "=> (Re)Starting local mail server (SMTP @ 1025, HTTP @ 1080)"
    docker stop {{smtp_server_container}} || true
    docker run -d --rm \
    -p 127.0.0.1:1080:1080 \
    -p 127.0.0.1:1025:1025 \
    --name {{smtp_server_container}} \
    {{smtp_server_image}}
    echo "==> You can open the test mail server at http://localhost:1080)"

# Stop the local SMTP server
@stop-local-mail-server:
    echo "=> Stopping local mail server..."
    docker stop {{smtp_server_container}} || true

# Start a detached wasmCloud host
@start-wasmcloud-host:
    echo "=> (Re)Starting detached wasmCloud host"
    {{wash}} up --detached

# Start a possibly detached wasmCloud host
@stop-wasmcloud-host:
    echo "=> (Re)Starting detached wasmCloud host"
    {{wash}} down
