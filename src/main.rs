use wit_bindgen_wrpc::anyhow;

use email_outgoing_provider::OutgoingEmailProvider;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    OutgoingEmailProvider::run().await?;
    eprintln!("Email outgoing provider exiting");
    Ok(())
}
