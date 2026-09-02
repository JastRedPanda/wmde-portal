// SPDX-License-Identifier: GPL-3.0-only

//! The screenshot face of the portal, and nothing more.
//!
//! Taking the picture belongs to `wmde-screenshot`, the program the desktop binds to Print.
//! This interface stays because the shared `xdg-desktop-portal` talks to the backend rather
//! than to applications, so every screenshot request on this desktop arrives here - it just
//! must not answer with a second, different screenshot interface beside the one a person
//! already uses.

use std::collections::HashMap;
use zbus::zvariant;

use crate::PortalResponse;

/// The program that owns screenshots on this desktop, and its object.
const SHOT_NAME: &str = "fun.wmde.Screenshot";
const SHOT_PATH: &str = "/fun/wmde/Screenshot";

#[derive(zvariant::DeserializeDict, zvariant::Type, Clone, Debug)]
#[zvariant(signature = "a{sv}")]
pub struct ScreenshotOptions {
    /// Read by nobody here, and kept anyway: the field has to exist for the dictionary to
    /// deserialise, and dropping it would make a caller that sets it fail instead of being
    /// ignored.
    #[allow(dead_code)]
    modal: Option<bool>,
    interactive: Option<bool>,
    /// Same: the destination is the screenshot program's business now.
    #[allow(dead_code)]
    choose_destination: Option<bool>,
}

#[derive(zvariant::SerializeDict, zvariant::Type)]
#[zvariant(signature = "a{sv}")]
pub struct ScreenshotResult {
    uri: String,
}

#[derive(zvariant::SerializeDict, zvariant::Type)]
#[zvariant(signature = "a{sv}")]
pub struct PickColorResult {
    color: (f64, f64, f64), // (ddd)
}

pub struct Screenshot;

#[zbus::interface(name = "org.freedesktop.impl.portal.Screenshot")]
impl Screenshot {
    async fn screenshot(
        &self,
        #[zbus(connection)] connection: &zbus::Connection,
        _handle: zvariant::ObjectPath<'_>,
        _app_id: &str,
        _parent_window: &str,
        options: ScreenshotOptions,
    ) -> PortalResponse<ScreenshotResult> {
        let interactive = options.interactive.unwrap_or_default();

        let proxy = match zbus::Proxy::new(connection, SHOT_NAME, SHOT_PATH, SHOT_NAME).await {
            Ok(proxy) => proxy,
            Err(err) => {
                tracing::error!("cannot reach {SHOT_NAME}: {err}");
                return PortalResponse::Other;
            }
        };

        // The call blocks for as long as the person takes to frame the shot, which is the
        // point: the caller is waiting for an image, and D-Bus is holding the request open
        // for exactly that reason.
        match proxy.call::<_, _, String>("Shot", &(interactive,)).await {
            Ok(uri) => PortalResponse::Success(ScreenshotResult { uri }),
            Err(err) => {
                // The one refusal that is not a fault: the person closed the overlay.
                if err.to_string().contains("cancelled") {
                    PortalResponse::Cancelled
                } else {
                    tracing::error!("{SHOT_NAME} took no screenshot: {err}");
                    PortalResponse::Other
                }
            }
        }
    }

    /// Never implemented here, and not forwarded: picking a colour off the screen is not
    /// something this desktop offers, so saying so is more honest than an empty overlay.
    async fn pick_color(
        &self,
        _handle: zvariant::ObjectPath<'_>,
        _app_id: &str,
        _parent_window: &str,
        _options: HashMap<String, zvariant::Value<'_>>,
    ) -> PortalResponse<PickColorResult> {
        PortalResponse::Other
    }

    #[zbus(property, name = "version")]
    fn version(&self) -> u32 {
        2
    }
}
