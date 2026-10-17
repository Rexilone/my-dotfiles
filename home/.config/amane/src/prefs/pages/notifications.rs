// Уведомления: «Не беспокоить», время показа, история (NotificationsPage.qml)

use amane::{Notifications, Service};

use super::super::w::{self, Btn, Card, Slide, W, bx};
use super::Out;
use crate::json::Json;
use crate::look::Tk;
use crate::notifs::{self, NotifState};
use crate::settings;
use crate::ui::ic;

pub fn page(t: &Tk, w: f32) -> Out {
    let dnd = NotifState::read().dnd;
    let n = Notifications::read().list().len();
    let mut items: Vec<W> = Vec::new();
    items.push(bx(Card::new(if dnd { ic::BELL_OFF } else { ic::BELL }, "Do not disturb", "Hide pop-ups; critical notifications and reminders still show")
        .ctrl(w::switch(t, "dnd", dnd, |_| notifs::toggle_dnd()))
        .build(t, w)));
    items.push(bx(Card::new(0xF051B, "Pop-up duration", "When the app doesn't set its own")
        .ctrl(Slide::new(t.c.popup_timeout as f64, 2.0, 15.0, 1.0).suffix(" s").build(t, "popup-timeout", |v| settings::save_key("popupTimeout", Json::Num(v.round()))))
        .build(t, w)));
    let desc = if t.c.ru() {
        format!("{n} {}", crate::i18n::plural(true, n as i64, "", "", "уведомление", "уведомления", "уведомлений"))
    } else {
        format!("{n} notification{}", if n == 1 { "" } else { "s" })
    };
    items.push(bx(Card::new(ic::TRASH, "Notification history", &desc).ctrl(Btn::new("Clear all").enabled(n > 0).build(t, "notif-clear", Notifications::clear)).build(t, w)));
    items.push(bx(Card::new(0xF00ED, "Send a test notification", "")
        .click(|| amane::spawn("notify-send -a Settings 'Test notification' 'This is how notifications look.'"))
        .build(t, w)));
    Out { crumb: String::new(), subtitle: "Pop-ups and Do not disturb".into(), items }
}
