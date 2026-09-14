//! Shared handle to the live UI, set once after the window is built.
//! Dialogs use it to trigger full refreshes after commits.

use std::cell::RefCell;
use std::rc::Rc;

use crate::ui::Ui;

thread_local! {
    static CURRENT: RefCell<Option<Rc<Ui>>> = const { RefCell::new(None) };
}

pub fn set(ui: Rc<Ui>) {
    CURRENT.with(|cell| *cell.borrow_mut() = Some(ui));
}

pub fn get() -> Option<Rc<Ui>> {
    CURRENT.with(|cell| cell.borrow().as_ref().map(Rc::clone))
}
