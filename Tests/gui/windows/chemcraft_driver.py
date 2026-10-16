"""Deterministic Windows ChemCraft GUI evidence driver.

The driver never writes into the ChemCraft installation. All captures, copied
fixtures, and structured logs are placed below tests/references/windows/runs.
It uses pywinauto's Win32 and UIA backends, with Pillow/PyAutoGUI screenshot
fallbacks for custom-drawn controls.
"""

from __future__ import annotations

import argparse
import ctypes
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import traceback
from typing import Any, Iterable

from PIL import Image, ImageChops, ImageGrab, ImageStat
import pyautogui
from pywinauto import Desktop
from pywinauto.keyboard import send_keys


PROJECT = Path(__file__).resolve().parents[3]
REFERENCE_ROOT = PROJECT / "tests" / "references" / "windows" / "runs"
DEFAULT_EXE = Path(r"C:\Chemcraft\Chemcraft.exe")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def configure_dpi_awareness() -> dict[str, Any]:
    result: dict[str, Any] = {}
    try:
        result["set_process_dpi_awareness_context"] = bool(
            ctypes.windll.user32.SetProcessDpiAwarenessContext(ctypes.c_void_p(-4))
        )
    except Exception as error:  # pragma: no cover - Windows-version dependent
        result["set_process_dpi_awareness_context_error"] = repr(error)
    user32 = ctypes.windll.user32
    result["screen_width_px"] = int(user32.GetSystemMetrics(0))
    result["screen_height_px"] = int(user32.GetSystemMetrics(1))
    try:
        result["system_dpi"] = int(user32.GetDpiForSystem())
        result["scale_percent"] = round(result["system_dpi"] * 100 / 96)
    except Exception as error:
        result["dpi_error"] = repr(error)
    return result


def _element_record(wrapper: Any, backend: str, depth: int, max_depth: int) -> dict[str, Any]:
    info = wrapper.element_info
    record: dict[str, Any] = {
        "backend": backend,
        "depth": depth,
        "handle": int(getattr(info, "handle", 0) or 0),
        "name": str(getattr(info, "name", "") or ""),
        "class_name": str(getattr(info, "class_name", "") or ""),
        "control_type": str(getattr(info, "control_type", "") or ""),
        "automation_id": str(getattr(info, "automation_id", "") or ""),
        "visible": bool(wrapper.is_visible()),
        "enabled": bool(wrapper.is_enabled()),
    }
    try:
        rect = wrapper.rectangle()
        record["rectangle"] = [rect.left, rect.top, rect.right, rect.bottom]
    except Exception as error:
        record["rectangle_error"] = repr(error)
    if depth < max_depth:
        children = []
        try:
            for child in wrapper.children():
                children.append(_element_record(child, backend, depth + 1, max_depth))
        except Exception as error:
            record["children_error"] = repr(error)
        record["children"] = children
    return record


def enumerate_windows(process_id: int, backend: str, max_depth: int = 6) -> list[dict[str, Any]]:
    records = []
    for window in Desktop(backend=backend).windows(process=process_id, visible_only=False):
        try:
            records.append(_element_record(window, backend, 0, max_depth))
        except Exception as error:
            records.append({"backend": backend, "enumeration_error": repr(error)})
    return records


def _menu_item_record(item: Any, depth: int = 0) -> dict[str, Any]:
    record: dict[str, Any] = {
        "depth": depth,
        "text": item.text(),
        "enabled": bool(item.is_enabled()),
        "checked": bool(item.is_checked()),
    }
    try:
        submenu = item.sub_menu()
        if submenu is not None:
            record["items"] = [_menu_item_record(child, depth + 1) for child in submenu.items()]
    except Exception as error:
        record["submenu_error"] = repr(error)
    return record


def inventory_native_menu(window: Any) -> dict[str, Any]:
    try:
        menu = window.menu()
        if menu is None:
            return {"available": False, "reason": "window.menu() returned None"}
        return {
            "available": True,
            "items": [_menu_item_record(item) for item in menu.items()],
        }
    except Exception as error:
        return {"available": False, "reason": repr(error)}


def wait_for_windows(process_id: int, timeout: float = 30.0) -> list[Any]:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        windows = Desktop(backend="win32").windows(process=process_id, visible_only=True)
        if windows:
            return windows
        time.sleep(0.25)
    raise TimeoutError(f"ChemCraft process {process_id} exposed no visible window in {timeout}s")


def choose_primary_window(windows: Iterable[Any]) -> Any:
    candidates = list(windows)
    if not candidates:
        raise RuntimeError("No candidate ChemCraft windows")
    return max(
        candidates,
        key=lambda window: max(0, window.rectangle().width()) * max(0, window.rectangle().height()),
    )


def wait_for_primary_window(process_id: int, timeout: float = 30.0) -> Any:
    deadline = time.monotonic() + timeout
    last_windows: list[Any] = []
    while time.monotonic() < deadline:
        last_windows = Desktop(backend="win32").windows(
            process=process_id, visible_only=True
        )
        main_forms = [
            window
            for window in last_windows
            if window.class_name() == "TMainForm"
            and window.rectangle().width() >= 800
            and window.rectangle().height() >= 600
        ]
        if main_forms:
            return choose_primary_window(main_forms)
        time.sleep(0.25)
    summary = [
        (window.window_text(), window.class_name(), _rect_list(window))
        for window in last_windows
    ]
    raise TimeoutError(f"No usable TMainForm for process {process_id}: {summary}")


def _rect_list(wrapper: Any) -> list[int]:
    rect = wrapper.rectangle()
    return [rect.left, rect.top, rect.right, rect.bottom]


def capture_window_region(window: Any, path: Path) -> None:
    """Capture by screen coordinates; Delphi's PrintWindow path returns 1x1."""
    window.set_focus()
    time.sleep(0.2)
    foreground_handle = int(ctypes.windll.user32.GetForegroundWindow())
    target_handle = int(window.handle)
    if foreground_handle != target_handle:
        raise RuntimeError(
            "Refusing screenshot: target window is not foreground "
            f"(target={target_handle}, foreground={foreground_handle})"
        )
    left, top, right, bottom = _rect_list(window)
    if right <= left or bottom <= top:
        raise ValueError(f"Invalid window rectangle: {(left, top, right, bottom)}")
    ImageGrab.grab(bbox=(left, top, right, bottom), all_screens=True).save(path)


def capture_images(window: Any, run_dir: Path) -> dict[str, Any]:
    captures: dict[str, Any] = {}
    try:
        path = run_dir / "chemcraft-window.png"
        capture_window_region(window, path)
        captures["window"] = str(path.relative_to(PROJECT))
    except Exception as error:
        captures["window_error"] = repr(error)
    try:
        path = run_dir / "desktop.png"
        ImageGrab.grab(all_screens=True).save(path)
        captures["desktop"] = str(path.relative_to(PROJECT))
    except Exception as error:
        captures["desktop_error"] = repr(error)
    return captures


def _visible_named_elements(process_id: int) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    seen: set[tuple[Any, ...]] = set()
    for window in Desktop(backend="uia").windows(process=process_id, visible_only=True):
        candidates = [window]
        try:
            candidates.extend(window.descendants())
        except Exception:
            pass
        for wrapper in candidates:
            try:
                info = wrapper.element_info
                name = str(getattr(info, "name", "") or "")
                if not name or not wrapper.is_visible():
                    continue
                rect = _rect_list(wrapper)
                key = (
                    name,
                    str(getattr(info, "control_type", "") or ""),
                    *rect,
                )
                if key in seen:
                    continue
                seen.add(key)
                records.append(
                    {
                        "name": name,
                        "class_name": str(getattr(info, "class_name", "") or ""),
                        "control_type": str(getattr(info, "control_type", "") or ""),
                        "enabled": bool(wrapper.is_enabled()),
                        "rectangle": rect,
                    }
                )
            except Exception:
                continue
    return records


def find_visible_element(process_id: int, title: str, control_type: str) -> Any:
    for window in Desktop(backend="uia").windows(
        process=process_id, visible_only=True
    ):
        for wrapper in [window, *window.descendants()]:
            try:
                info = wrapper.element_info
                if (
                    wrapper.is_visible()
                    and str(getattr(info, "name", "") or "") == title
                    and str(getattr(info, "control_type", "") or "")
                    == control_type
                ):
                    return wrapper
            except Exception:
                continue
    raise RuntimeError(f"No visible {control_type} named {title!r}")


def wait_for_secondary_window(
    process_id: int, primary_handle: int, timeout: float = 10.0
) -> Any:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        windows = Desktop(backend="win32").windows(
            process=process_id, visible_only=True
        )
        secondary = [
            window
            for window in windows
            if window.handle != primary_handle
            and window.rectangle().width() > 100
            and window.rectangle().height() > 80
        ]
        if secondary:
            return choose_primary_window(secondary)
        time.sleep(0.2)
    raise TimeoutError(f"No secondary window appeared for process {process_id}")


def open_file_through_dialog(
    process_id: int, primary: Any, source_path: Path
) -> dict[str, Any]:
    result: dict[str, Any] = {"requested_path": str(source_path)}
    primary.set_focus()
    send_keys("^o")
    dialog = wait_for_secondary_window(process_id, primary.handle)
    result["dialog"] = {
        "title": dialog.window_text(),
        "class_name": dialog.class_name(),
        "rectangle": _rect_list(dialog),
    }
    dialog_uia = Desktop(backend="uia").window(handle=dialog.handle)
    result["dialog_elements"] = []
    for wrapper in [dialog_uia, *dialog_uia.descendants()]:
        try:
            info = wrapper.element_info
            name = str(getattr(info, "name", "") or "")
            control_type = str(getattr(info, "control_type", "") or "")
            automation_id = str(getattr(info, "automation_id", "") or "")
            if name or control_type in {"Edit", "Button", "ComboBox"}:
                result["dialog_elements"].append(
                    {
                        "name": name,
                        "control_type": control_type,
                        "automation_id": automation_id,
                        "rectangle": _rect_list(wrapper),
                    }
                )
        except Exception:
            continue
    filename_edits = [
        wrapper
        for wrapper in dialog_uia.descendants(control_type="Edit")
        if wrapper.is_visible() and wrapper.is_enabled()
    ]
    if not filename_edits:
        raise RuntimeError("Open dialog exposed no usable Edit control")
    named_filename_edits = [
        wrapper
        for wrapper in filename_edits
        if str(getattr(wrapper.element_info, "automation_id", "")) == "1148"
    ]
    filename_edit = (
        named_filename_edits[0]
        if named_filename_edits
        else max(filename_edits, key=lambda wrapper: wrapper.rectangle().bottom)
    )
    result["selected_filename_edit"] = {
        "automation_id": str(
            getattr(filename_edit.element_info, "automation_id", "") or ""
        ),
        "rectangle": _rect_list(filename_edit),
    }
    filename_edit.click_input()
    filename_edit.set_edit_text(str(source_path))
    open_buttons = [
        wrapper
        for wrapper in dialog_uia.descendants()
        if wrapper.is_visible()
        and wrapper.is_enabled()
        and wrapper.window_text().replace("&", "").strip().lower() == "open"
        and str(getattr(wrapper.element_info, "automation_id", "")) == "1"
    ]
    if not open_buttons:
        raise RuntimeError("Open dialog exposed no enabled Open button")
    result["selected_open_button"] = {
        "control_type": str(
            getattr(open_buttons[0].element_info, "control_type", "") or ""
        ),
        "automation_id": str(
            getattr(open_buttons[0].element_info, "automation_id", "") or ""
        ),
        "rectangle": _rect_list(open_buttons[0]),
    }
    open_buttons[0].click_input()
    deadline = time.monotonic() + 30.0
    while time.monotonic() < deadline:
        visible_handles = {
            window.handle
            for window in Desktop(backend="win32").windows(
                process=process_id, visible_only=True
            )
        }
        if dialog.handle not in visible_handles:
            break
        time.sleep(0.2)
    else:
        raise TimeoutError("Open dialog did not close")
    time.sleep(1.5)
    result["window_title_after_open"] = primary.window_text()
    result["visible_windows_after_open"] = [
        {
            "title": window.window_text(),
            "class_name": window.class_name(),
            "rectangle": _rect_list(window),
        }
        for window in Desktop(backend="win32").windows(
            process=process_id, visible_only=True
        )
    ]
    return result


def image_difference(before: Path, after: Path) -> dict[str, Any]:
    first = Image.open(before).convert("RGB")
    second = Image.open(after).convert("RGB")
    difference = ImageChops.difference(first, second)
    histogram = difference.convert("L").histogram()
    changed = sum(histogram[1:])
    total = first.width * first.height
    return {
        "size": [first.width, first.height],
        "changed_pixel_fraction": changed / total,
        "difference_bbox": list(difference.getbbox()) if difference.getbbox() else None,
        "rms_rgb": [round(value, 4) for value in ImageStat.Stat(difference).rms],
    }


def find_viewport(primary: Any) -> list[int]:
    candidates = []
    primary_rect = primary.rectangle()
    for wrapper in primary.descendants():
        try:
            rect = wrapper.rectangle()
            if (
                wrapper.class_name() == "TPanel"
                and rect.width() > 500
                and rect.height() > 400
                and rect.width() < primary_rect.width()
                and rect.top >= primary_rect.top + 100
                and rect.bottom <= primary_rect.bottom - 25
            ):
                candidates.append(wrapper)
        except Exception:
            continue
    if not candidates:
        raise RuntimeError("Unable to identify the custom-drawn viewport")
    return _rect_list(
        max(
            candidates,
            key=lambda wrapper: wrapper.rectangle().width()
            * wrapper.rectangle().height(),
        )
    )


def audit_xyz_workflow(executable: Path, fixture: Path, keep_open: bool) -> Path:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    run_dir = REFERENCE_ROOT / stamp
    run_dir.mkdir(parents=True, exist_ok=False)
    copied_fixture = run_dir / fixture.name
    shutil.copy2(fixture, copied_fixture)
    result: dict[str, Any] = {
        "schema": 1,
        "started_at_utc": stamp,
        "command": "xyz-workflow",
        "executable": str(executable),
        "executable_sha256": sha256(executable),
        "fixture_source": str(fixture),
        "fixture_copy": str(copied_fixture.relative_to(PROJECT)),
        "fixture_sha256": sha256(copied_fixture),
        "environment": configure_dpi_awareness(),
        "status": "starting",
    }
    process: subprocess.Popen[Any] | None = None
    try:
        process = subprocess.Popen([str(executable)], cwd=str(executable.parent))
        result["process_id"] = process.pid
        primary = wait_for_primary_window(process.pid)
        result["open"] = open_file_through_dialog(process.pid, primary, copied_fixture)
        result["viewport_rectangle"] = find_viewport(primary)
        result["modes"] = []
        uia_window = Desktop(backend="uia").window(handle=primary.handle)
        for index, mode_name in enumerate(["Image", "Abstract", "Source", "Coord"]):
            mode_result: dict[str, Any] = {"name": mode_name}
            try:
                mode = uia_window.child_window(
                    title=mode_name, control_type="RadioButton"
                ).wrapper_object()
                mode_result["enabled"] = bool(mode.is_enabled())
                if mode.is_enabled():
                    mode.click_input()
                    time.sleep(0.5)
                    path = run_dir / f"mode-{index + 1:02d}-{mode_name.lower()}.png"
                    capture_window_region(primary, path)
                    mode_result["screenshot"] = str(path.relative_to(PROJECT))
                    mode_result["visible_named_elements"] = _visible_named_elements(
                        process.pid
                    )
                mode_result["status"] = "observed"
            except Exception as error:
                mode_result["status"] = "error"
                mode_result["error"] = repr(error)
            result["modes"].append(mode_result)

        image_mode = uia_window.child_window(
            title="Image", control_type="RadioButton"
        ).wrapper_object()
        image_mode.click_input()
        time.sleep(0.4)
        viewport = result["viewport_rectangle"]
        center_x = (viewport[0] + viewport[2]) // 2
        center_y = (viewport[1] + viewport[3]) // 2
        interactions: list[dict[str, Any]] = []

        rotate_before = run_dir / "rotate-before.png"
        rotate_after = run_dir / "rotate-after.png"
        capture_window_region(primary, rotate_before)
        pyautogui.moveTo(center_x, center_y, duration=0.15)
        pyautogui.dragRel(180, 90, duration=0.7, button="left")
        time.sleep(0.5)
        capture_window_region(primary, rotate_after)
        interactions.append(
            {
                "action": "left-drag",
                "start": [center_x, center_y],
                "delta": [180, 90],
                "before": str(rotate_before.relative_to(PROJECT)),
                "after": str(rotate_after.relative_to(PROJECT)),
                "difference": image_difference(rotate_before, rotate_after),
            }
        )

        right_before = run_dir / "right-drag-before.png"
        right_after = run_dir / "right-drag-after.png"
        capture_window_region(primary, right_before)
        pyautogui.moveTo(center_x, center_y, duration=0.15)
        pyautogui.dragRel(180, 90, duration=0.7, button="right")
        time.sleep(0.5)
        capture_window_region(primary, right_after)
        interactions.append(
            {
                "action": "right-drag",
                "start": [center_x, center_y],
                "delta": [180, 90],
                "before": str(right_before.relative_to(PROJECT)),
                "after": str(right_after.relative_to(PROJECT)),
                "difference": image_difference(right_before, right_after),
            }
        )

        zoom_before = run_dir / "zoom-before.png"
        zoom_after = run_dir / "zoom-after.png"
        capture_window_region(primary, zoom_before)
        pyautogui.moveTo(center_x, center_y, duration=0.15)
        pyautogui.scroll(4)
        time.sleep(0.5)
        capture_window_region(primary, zoom_after)
        interactions.append(
            {
                "action": "mouse-wheel",
                "position": [center_x, center_y],
                "clicks": 4,
                "before": str(zoom_before.relative_to(PROJECT)),
                "after": str(zoom_after.relative_to(PROJECT)),
                "difference": image_difference(zoom_before, zoom_after),
            }
        )

        toolbar_actions = [
            ("toolbar-rotate-clockwise", [viewport[2] + 15, viewport[1] + 14]),
            ("toolbar-zoom-in", [viewport[2] + 15, viewport[1] + 261]),
            ("toolbar-translate-up", [viewport[2] + 15, viewport[1] + 338]),
        ]
        for action_name, position in toolbar_actions:
            before = run_dir / f"{action_name}-before.png"
            after = run_dir / f"{action_name}-after.png"
            capture_window_region(primary, before)
            pyautogui.click(position[0], position[1])
            time.sleep(0.5)
            capture_window_region(primary, after)
            interactions.append(
                {
                    "action": action_name,
                    "position": position,
                    "calibration": "main-window-relative at 2560x1440, 100% scale",
                    "before": str(before.relative_to(PROJECT)),
                    "after": str(after.relative_to(PROJECT)),
                    "difference": image_difference(before, after),
                }
            )
        result["interactions"] = interactions
        result["final_visible_named_elements"] = _visible_named_elements(process.pid)
        result["status"] = "observed"
        if keep_open:
            result["process_left_running"] = True
    except Exception as error:
        result["status"] = "error"
        result["error"] = repr(error)
        result["traceback"] = traceback.format_exc()
        raise
    finally:
        write_json(run_dir / "workflow.json", result)
        if process is not None and not keep_open:
            try:
                windows = Desktop(backend="win32").windows(
                    process=process.pid, visible_only=True
                )
                if windows:
                    choose_primary_window(windows).close()
                process.wait(timeout=8)
            except Exception:
                pass
    return run_dir


def audit_orca_navigation(executable: Path, fixture: Path, keep_open: bool) -> Path:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    run_dir = REFERENCE_ROOT / stamp
    run_dir.mkdir(parents=True, exist_ok=False)
    copied_fixture = run_dir / fixture.name
    shutil.copy2(fixture, copied_fixture)
    result: dict[str, Any] = {
        "schema": 1,
        "started_at_utc": stamp,
        "command": "orca-navigation",
        "executable": str(executable),
        "executable_sha256": sha256(executable),
        "fixture_source": str(fixture),
        "fixture_copy": str(copied_fixture.relative_to(PROJECT)),
        "fixture_sha256": sha256(copied_fixture),
        "environment": configure_dpi_awareness(),
        "status": "starting",
    }
    process: subprocess.Popen[Any] | None = None
    try:
        process = subprocess.Popen([str(executable)], cwd=str(executable.parent))
        result["process_id"] = process.pid
        primary = wait_for_primary_window(process.pid)
        result["open"] = open_file_through_dialog(process.pid, primary, copied_fixture)
        uia_window = Desktop(backend="uia").window(handle=primary.handle)
        result["branches"] = []
        for index, branch_name in enumerate(["Optimization", "Frequencies"]):
            branch_result: dict[str, Any] = {"name": branch_name}
            try:
                branch = uia_window.child_window(
                    title=branch_name, control_type="TreeItem"
                ).wrapper_object()
                branch_result["rectangle"] = _rect_list(branch)
                branch.click_input()
                try:
                    branch.expand()
                    branch_result["expand_method"] = "UIA expand"
                except Exception as expand_error:
                    send_keys("{RIGHT}")
                    branch_result["expand_method"] = "Right Arrow fallback"
                    branch_result["expand_error"] = repr(expand_error)
                time.sleep(0.6)
                branch_result["tree_items"] = [
                    {
                        "name": item.window_text(),
                        "rectangle": _rect_list(item),
                        "enabled": bool(item.is_enabled()),
                    }
                    for item in uia_window.descendants(control_type="TreeItem")
                    if item.is_visible()
                ]
                path = run_dir / f"branch-{index + 1:02d}-{branch_name.lower()}.png"
                capture_window_region(primary, path)
                branch_result["screenshot"] = str(path.relative_to(PROJECT))
                branch_result["visible_named_elements"] = _visible_named_elements(
                    process.pid
                )
                branch_result["status"] = "observed"
            except Exception as error:
                branch_result["status"] = "error"
                branch_result["error"] = repr(error)
                branch_result["traceback"] = traceback.format_exc()
            result["branches"].append(branch_result)
        spectrum_result: dict[str, Any] = {
            "trigger": "custom-drawn Show spectrum control",
            "calibration": "main-window-relative at 2560x1440, 100% scale",
        }
        try:
            main_rect = primary.rectangle()
            spectrum_position = [main_rect.left + 131, main_rect.bottom - 212]
            spectrum_result["position"] = spectrum_position
            pyautogui.click(*spectrum_position)
            time.sleep(0.8)
            spectrum_windows = Desktop(backend="win32").windows(
                process=process.pid, visible_only=True
            )
            spectrum_result["visible_windows"] = [
                {
                    "title": window.window_text(),
                    "class_name": window.class_name(),
                    "rectangle": _rect_list(window),
                }
                for window in spectrum_windows
            ]
            spectrum_window = choose_primary_window(spectrum_windows)
            spectrum_path = run_dir / "frequency-spectrum.png"
            capture_window_region(spectrum_window, spectrum_path)
            spectrum_result["screenshot"] = str(spectrum_path.relative_to(PROJECT))
            spectrum_result["visible_named_elements"] = _visible_named_elements(
                process.pid
            )
            spectrum_result["status"] = "observed"
            send_keys("{ESC}")
            time.sleep(0.2)
        except Exception as error:
            spectrum_result["status"] = "error"
            spectrum_result["error"] = repr(error)
        result["spectrum"] = spectrum_result
        result["context_menus"] = []
        for index, item_name in enumerate(
            ["Optimization steps", "Frequencies", "7: Frequency 1606.12"]
        ):
            context_result: dict[str, Any] = {"tree_item": item_name}
            try:
                item = uia_window.child_window(
                    title=item_name, control_type="TreeItem"
                ).wrapper_object()
                item.right_click_input()
                time.sleep(0.5)
                path = run_dir / f"context-{index + 1:02d}.png"
                capture_window_region(primary, path)
                context_result["screenshot"] = str(path.relative_to(PROJECT))
                context_result["visible_named_elements"] = _visible_named_elements(
                    process.pid
                )
                context_result["status"] = "observed"
            except Exception as error:
                context_result["status"] = "error"
                context_result["error"] = repr(error)
            finally:
                send_keys("{ESC}")
                time.sleep(0.15)
            result["context_menus"].append(context_result)
        result["selections"] = []
        selection_specs = [
            ("optimization-steps", "Optimization steps"),
            ("frequency-1606.12", "7: Frequency 1606.12"),
        ]
        for selection_name, item_name in selection_specs:
            selection: dict[str, Any] = {
                "name": selection_name,
                "tree_item": item_name,
            }
            try:
                item = uia_window.child_window(
                    title=item_name, control_type="TreeItem"
                ).wrapper_object()
                item.click_input()
                time.sleep(0.6)
                first = run_dir / f"selection-{selection_name}-01.png"
                second = run_dir / f"selection-{selection_name}-02.png"
                capture_window_region(primary, first)
                time.sleep(0.8)
                capture_window_region(primary, second)
                selection["first_screenshot"] = str(first.relative_to(PROJECT))
                selection["second_screenshot"] = str(second.relative_to(PROJECT))
                selection["time_difference"] = image_difference(first, second)
                selection["visible_named_elements"] = _visible_named_elements(
                    process.pid
                )
                if selection_name == "optimization-steps":
                    animation_toggle = uia_window.child_window(
                        title="Animate optimization steps", control_type="CheckBox"
                    ).wrapper_object()
                    animation_toggle.click_input()
                    time.sleep(0.2)
                    animated_first = run_dir / "optimization-animation-01.png"
                    animated_second = run_dir / "optimization-animation-02.png"
                    capture_window_region(primary, animated_first)
                    time.sleep(1.0)
                    capture_window_region(primary, animated_second)
                    selection["animation_enabled"] = True
                    selection["animation_first"] = str(
                        animated_first.relative_to(PROJECT)
                    )
                    selection["animation_second"] = str(
                        animated_second.relative_to(PROJECT)
                    )
                    selection["animation_difference"] = image_difference(
                        animated_first, animated_second
                    )
                    animation_toggle.click_input()
                elif selection_name == "frequency-1606.12":
                    selection["vectors_control_observed"] = True
                    selection["vectors_automation_status"] = (
                        "manual-required: an isolated click attempt caused the "
                        "application window and driver to become unresponsive"
                    )
                selection["status"] = "observed"
            except Exception as error:
                selection["status"] = "error"
                selection["error"] = repr(error)
            result["selections"].append(selection)
        result["status"] = (
            "observed"
            if all(branch["status"] == "observed" for branch in result["branches"])
            else "partial"
        )
        if keep_open:
            result["process_left_running"] = True
    except Exception as error:
        result["status"] = "error"
        result["error"] = repr(error)
        result["traceback"] = traceback.format_exc()
        raise
    finally:
        write_json(run_dir / "orca-navigation.json", result)
        if process is not None and not keep_open:
            try:
                windows = Desktop(backend="win32").windows(
                    process=process.pid, visible_only=True
                )
                if windows:
                    choose_primary_window(windows).close()
                process.wait(timeout=8)
            except Exception:
                pass
    return run_dir


def audit_result_tree(executable: Path, fixture: Path, keep_open: bool) -> Path:
    """Expand the result tree without assuming a program-specific hierarchy."""
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    run_dir = REFERENCE_ROOT / stamp
    run_dir.mkdir(parents=True, exist_ok=False)
    copied_fixture = run_dir / fixture.name
    shutil.copy2(fixture, copied_fixture)
    result: dict[str, Any] = {
        "schema": 1,
        "started_at_utc": stamp,
        "command": "result-tree",
        "executable": str(executable),
        "executable_sha256": sha256(executable),
        "fixture_source": str(fixture),
        "fixture_copy": str(copied_fixture.relative_to(PROJECT)),
        "fixture_sha256": sha256(copied_fixture),
        "environment": configure_dpi_awareness(),
        "status": "starting",
    }
    process: subprocess.Popen[Any] | None = None
    try:
        process = subprocess.Popen([str(executable)], cwd=str(executable.parent))
        result["process_id"] = process.pid
        primary = wait_for_primary_window(process.pid)
        result["open"] = open_file_through_dialog(process.pid, primary, copied_fixture)
        time.sleep(0.6)
        windows = Desktop(backend="win32").windows(process=process.pid, visible_only=True)
        result["visible_windows_after_open"] = [
            {
                "title": window.window_text(),
                "class_name": window.class_name(),
                "rectangle": _rect_list(window),
            }
            for window in windows
        ]
        blocking = []
        for window in windows:
            rectangle = window.rectangle()
            if (
                window.class_name() != "TMainForm"
                and window.is_enabled()
                and rectangle.width() > 20
                and rectangle.height() > 20
            ):
                blocking.append(window)
        if blocking:
            result["status"] = "blocked-by-secondary-dialog"
            result["blocking_dialogs"] = [
                {"title": window.window_text(), "class_name": window.class_name()}
                for window in blocking
            ]
            capture_window_region(blocking[0], run_dir / "blocking-dialog.png")
            return run_dir

        primary = wait_for_primary_window(process.pid)
        uia_window = Desktop(backend="uia").window(handle=primary.handle)
        result["passes"] = []
        seen: set[str] = set()
        for pass_index in range(3):
            pass_result: dict[str, Any] = {"pass": pass_index + 1, "attempts": []}
            items = [
                item for item in uia_window.descendants(control_type="TreeItem")
                if item.is_visible() and item.window_text()
            ]
            pass_result["visible_items_before"] = [item.window_text() for item in items]
            for item in items:
                name = item.window_text()
                if name in seen:
                    continue
                seen.add(name)
                attempt: dict[str, Any] = {"name": name, "rectangle": _rect_list(item)}
                try:
                    item.expand()
                    attempt["result"] = "expanded"
                except Exception as error:
                    attempt["error"] = repr(error)
                    try:
                        item.click_input()
                        send_keys("{RIGHT}")
                        attempt["result"] = "right-arrow-fallback"
                    except Exception as fallback_error:
                        attempt["result"] = "not-expandable-or-error"
                        attempt["fallback_error"] = repr(fallback_error)
                pass_result["attempts"].append(attempt)
                time.sleep(0.1)
            time.sleep(0.4)
            pass_result["visible_items_after"] = [
                item.window_text()
                for item in uia_window.descendants(control_type="TreeItem")
                if item.is_visible() and item.window_text()
            ]
            screenshot = run_dir / f"tree-pass-{pass_index + 1:02d}.png"
            capture_window_region(primary, screenshot)
            pass_result["screenshot"] = str(screenshot.relative_to(PROJECT))
            result["passes"].append(pass_result)
            if pass_result["visible_items_after"] == pass_result["visible_items_before"]:
                break
        result["status"] = "observed"
    except Exception as error:
        result["status"] = "error"
        result["error"] = repr(error)
        result["traceback"] = traceback.format_exc()
        raise
    finally:
        write_json(run_dir / "result-tree.json", result)
        if process is not None and not keep_open:
            try:
                windows = Desktop(backend="win32").windows(
                    process=process.pid, visible_only=True
                )
                for window in windows:
                    try:
                        window.close()
                    except Exception:
                        pass
                process.wait(timeout=8)
            except Exception:
                pass
    return run_dir


def audit_measurements(executable: Path, fixture: Path, keep_open: bool) -> Path:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    run_dir = REFERENCE_ROOT / stamp
    run_dir.mkdir(parents=True, exist_ok=False)
    copied_fixture = run_dir / fixture.name
    shutil.copy2(fixture, copied_fixture)
    result: dict[str, Any] = {
        "schema": 1,
        "started_at_utc": stamp,
        "command": "measurements",
        "fixture_source": str(fixture),
        "fixture_copy": str(copied_fixture.relative_to(PROJECT)),
        "fixture_sha256": sha256(copied_fixture),
        "status": "starting",
    }
    process: subprocess.Popen[Any] | None = None
    try:
        process = subprocess.Popen([str(executable)], cwd=str(executable.parent))
        result["process_id"] = process.pid
        primary = wait_for_primary_window(process.pid)
        result["open"] = open_file_through_dialog(process.pid, primary, copied_fixture)
        viewport = find_viewport(primary)
        center_x = (viewport[0] + viewport[2]) // 2
        atom_positions = [
            [center_x - 320, viewport[1] + 640],
            [center_x, viewport[1] + 390],
            [center_x + 320, viewport[1] + 640],
        ]
        result["calibrated_atom_positions"] = atom_positions
        baseline = run_dir / "selection-00-baseline.png"
        capture_window_region(primary, baseline)
        selection_steps = []
        for index, position in enumerate(atom_positions, start=1):
            if index > 1:
                pyautogui.keyDown("ctrl")
            pyautogui.click(*position)
            if index > 1:
                pyautogui.keyUp("ctrl")
            time.sleep(0.35)
            path = run_dir / f"selection-{index:02d}.png"
            capture_window_region(primary, path)
            prior = baseline if index == 1 else run_dir / f"selection-{index - 1:02d}.png"
            edit_values = []
            for wrapper in primary.descendants():
                try:
                    if wrapper.class_name() == "TEdit" and wrapper.window_text().strip():
                        edit_values.append(wrapper.window_text().strip())
                except Exception:
                    continue
            selection_steps.append(
                {
                    "atom_index": index,
                    "position": position,
                    "screenshot": str(path.relative_to(PROJECT)),
                    "difference_from_prior": image_difference(prior, path),
                    "visible_edit_values": edit_values,
                }
            )
        result["selection_steps"] = selection_steps
        result["win32_text_after_selection"] = []
        for wrapper in primary.descendants():
            try:
                text_value = wrapper.window_text().strip()
                if text_value:
                    result["win32_text_after_selection"].append(
                        {
                            "text": text_value,
                            "class_name": wrapper.class_name(),
                            "rectangle": _rect_list(wrapper),
                        }
                    )
            except Exception:
                continue

        uia_window = Desktop(backend="uia").window(handle=primary.handle)
        view_menu = uia_window.child_window(
            title="View", control_type="MenuItem"
        ).wrapper_object()
        view_menu.click_input()
        time.sleep(0.2)
        structural_item = find_visible_element(
            process.pid,
            "Show structural parameters (of whole molecule or selected atoms)",
            "MenuItem",
        )
        result["structural_parameters_menu_enabled"] = bool(
            structural_item.is_enabled()
        )
        structural_item.click_input()
        time.sleep(0.35)
        structural_path = run_dir / "structural-parameters-menu.png"
        capture_window_region(primary, structural_path)
        result["structural_parameters_menu_screenshot"] = str(
            structural_path.relative_to(PROJECT)
        )
        result["structural_parameter_overlays"] = []
        for index, overlay_name in enumerate(
            ["Show all bond lengths", "Show all bond angles"], start=1
        ):
            if index > 1:
                view_menu.click_input()
                time.sleep(0.15)
                structural_item = find_visible_element(
                    process.pid,
                    "Show structural parameters (of whole molecule or selected atoms)",
                    "MenuItem",
                )
                structural_item.click_input()
                time.sleep(0.3)
            overlay_item = find_visible_element(
                process.pid, overlay_name, "MenuItem"
            )
            overlay_item.click_input()
            time.sleep(0.5)
            overlay_path = run_dir / f"structural-overlay-{index:02d}.png"
            capture_window_region(primary, overlay_path)
            result["structural_parameter_overlays"].append(
                {
                    "name": overlay_name,
                    "screenshot": str(overlay_path.relative_to(PROJECT)),
                }
            )
        result["visible_named_elements"] = _visible_named_elements(process.pid)
        result["status"] = "observed"
        if keep_open:
            result["process_left_running"] = True
    except Exception as error:
        result["status"] = "error"
        result["error"] = repr(error)
        result["traceback"] = traceback.format_exc()
        raise
    finally:
        write_json(run_dir / "measurements.json", result)
        if process is not None and not keep_open:
            try:
                send_keys("{ESC}")
                windows = Desktop(backend="win32").windows(
                    process=process.pid, visible_only=True
                )
                main_forms = [w for w in windows if w.class_name() == "TMainForm"]
                if main_forms:
                    choose_primary_window(main_forms).close()
                process.wait(timeout=8)
            except Exception:
                pass
    return run_dir


def audit_select_all(executable: Path, fixture: Path, keep_open: bool) -> Path:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    run_dir = REFERENCE_ROOT / stamp
    run_dir.mkdir(parents=True, exist_ok=False)
    copied_fixture = run_dir / fixture.name
    shutil.copy2(fixture, copied_fixture)
    result: dict[str, Any] = {
        "schema": 1,
        "started_at_utc": stamp,
        "command": "select-all",
        "fixture_source": str(fixture),
        "fixture_copy": str(copied_fixture.relative_to(PROJECT)),
        "fixture_sha256": sha256(copied_fixture),
        "status": "starting",
    }
    process: subprocess.Popen[Any] | None = None
    try:
        process = subprocess.Popen([str(executable)], cwd=str(executable.parent))
        result["process_id"] = process.pid
        primary = wait_for_primary_window(process.pid)
        result["open"] = open_file_through_dialog(process.pid, primary, copied_fixture)
        baseline = run_dir / "select-all-before.png"
        capture_window_region(primary, baseline)
        uia_window = Desktop(backend="uia").window(handle=primary.handle)
        uia_window.child_window(title="Edit", control_type="MenuItem").wrapper_object().click_input()
        time.sleep(0.2)
        select_all = find_visible_element(process.pid, "Select all", "MenuItem")
        select_all.click_input()
        time.sleep(0.5)
        after = run_dir / "select-all-after.png"
        capture_window_region(primary, after)
        result["difference"] = image_difference(baseline, after)
        result["visible_edit_values"] = [
            wrapper.window_text().strip()
            for wrapper in primary.descendants()
            if wrapper.class_name() == "TEdit" and wrapper.window_text().strip()
        ]
        result["win32_text"] = [
            {
                "text": wrapper.window_text().strip(),
                "class_name": wrapper.class_name(),
                "rectangle": _rect_list(wrapper),
            }
            for wrapper in primary.descendants()
            if wrapper.window_text().strip()
        ]
        result["screenshot"] = str(after.relative_to(PROJECT))
        result["status"] = "observed"
        if keep_open:
            result["process_left_running"] = True
    except Exception as error:
        result["status"] = "error"
        result["error"] = repr(error)
        result["traceback"] = traceback.format_exc()
        raise
    finally:
        write_json(run_dir / "select-all.json", result)
        if process is not None and not keep_open:
            try:
                windows = Desktop(backend="win32").windows(
                    process=process.pid, visible_only=True
                )
                main_forms = [w for w in windows if w.class_name() == "TMainForm"]
                if main_forms:
                    choose_primary_window(main_forms).close()
                process.wait(timeout=8)
            except Exception:
                pass
    return run_dir


def audit_orbital_entry(executable: Path, fixture: Path, keep_open: bool) -> Path:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    run_dir = REFERENCE_ROOT / stamp
    run_dir.mkdir(parents=True, exist_ok=False)
    copied_fixture = run_dir / fixture.name
    shutil.copy2(fixture, copied_fixture)
    result: dict[str, Any] = {
        "schema": 1,
        "started_at_utc": stamp,
        "command": "orbital-entry",
        "fixture_source": str(fixture),
        "fixture_copy": str(copied_fixture.relative_to(PROJECT)),
        "fixture_sha256": sha256(copied_fixture),
        "status": "starting",
    }
    process: subprocess.Popen[Any] | None = None
    try:
        process = subprocess.Popen([str(executable)], cwd=str(executable.parent))
        result["process_id"] = process.pid
        primary = wait_for_primary_window(process.pid)
        result["open"] = open_file_through_dialog(process.pid, primary, copied_fixture)
        uia_window = Desktop(backend="uia").window(handle=primary.handle)
        uia_window.child_window(title="Tools", control_type="MenuItem").wrapper_object().click_input()
        time.sleep(0.2)
        orbitals = find_visible_element(process.pid, "Orbitals", "MenuItem")
        orbitals_rect = orbitals.rectangle()
        pyautogui.moveTo(
            (orbitals_rect.left + orbitals_rect.right) // 2,
            (orbitals_rect.top + orbitals_rect.bottom) // 2,
            duration=0.1,
        )
        time.sleep(0.35)
        render_item = find_visible_element(
            process.pid, "Render molecular orbitals", "MenuItem"
        )
        result["render_command_enabled"] = bool(render_item.is_enabled())
        render_item.click_input()
        dialog = wait_for_secondary_window(process.pid, primary.handle, timeout=15)
        time.sleep(0.4)
        result["dialog"] = {
            "title": dialog.window_text(),
            "class_name": dialog.class_name(),
            "rectangle": _rect_list(dialog),
        }
        path = run_dir / "orbital-dialog.png"
        capture_window_region(dialog, path)
        result["dialog_screenshot"] = str(path.relative_to(PROJECT))
        result["visible_named_elements"] = _visible_named_elements(process.pid)
        dialog_uia = Desktop(backend="uia").window(handle=dialog.handle)
        occupied_items = [
            item
            for item in dialog_uia.descendants(control_type="ListItem")
            if "(Occ.," in item.window_text()
        ]
        if not occupied_items:
            raise RuntimeError("Orbital dialog exposed no occupied molecular orbitals")
        homo = occupied_items[-1]
        result["selected_orbital"] = homo.window_text()
        homo_rect = homo.rectangle()
        checkbox_position = [homo_rect.left + 6, (homo_rect.top + homo_rect.bottom) // 2]
        result["orbital_checkbox_position"] = checkbox_position
        pyautogui.click(*checkbox_position)
        time.sleep(0.2)
        selected_path = run_dir / "orbital-dialog-selected.png"
        capture_window_region(dialog, selected_path)
        result["selected_dialog_screenshot"] = str(
            selected_path.relative_to(PROJECT)
        )
        ok_buttons = [
            button
            for button in dialog_uia.descendants(control_type="Button")
            if button.window_text().replace("&", "").strip().lower() == "ok"
        ]
        if not ok_buttons:
            ok_buttons = [
                button
                for button in dialog.descendants()
                if button.window_text().replace("&", "").strip().lower() == "ok"
                and button.is_visible()
                and button.is_enabled()
            ]
        if not ok_buttons:
            dialog_rect = dialog.rectangle()
            calibrated_ok = [dialog_rect.right - 125, dialog_rect.bottom - 32]
            result["ok_control_fallback"] = {
                "position": calibrated_ok,
                "reason": "custom Delphi button was not exposed by UIA or Win32",
            }
            pyautogui.click(*calibrated_ok)
        else:
            ok_buttons[0].click_input()
        deadline = time.monotonic() + 45.0
        while time.monotonic() < deadline:
            visible = Desktop(backend="win32").windows(
                process=process.pid, visible_only=True
            )
            blockers = [
                window
                for window in visible
                if window.handle != primary.handle
                and window.rectangle().width() > 100
                and window.rectangle().height() > 80
            ]
            if not blockers:
                break
            time.sleep(0.25)
        else:
            result["render_timeout"] = True
        time.sleep(0.8)
        orbital_nodes = [
            item
            for item in Desktop(backend="uia")
            .window(handle=primary.handle)
            .descendants(control_type="TreeItem")
            if item.window_text().startswith("Alpha molecular orbital  5")
        ]
        if orbital_nodes:
            orbital_nodes[0].click_input()
            result["orbital_tree_node_selected"] = True
            time.sleep(1.0)
            primary_rect = primary.rectangle()
            show_isosurface_position = [
                primary_rect.left + 58,
                primary_rect.bottom - 359,
            ]
            result["show_isosurface_position"] = show_isosurface_position
            pyautogui.click(*show_isosurface_position)
            time.sleep(1.0)
        rendered_path = run_dir / "orbital-rendered.png"
        capture_window_region(primary, rendered_path)
        result["rendered_screenshot"] = str(rendered_path.relative_to(PROJECT))
        result["visible_windows_after_render"] = [
            {
                "title": window.window_text(),
                "class_name": window.class_name(),
                "rectangle": _rect_list(window),
            }
            for window in Desktop(backend="win32").windows(
                process=process.pid, visible_only=True
            )
        ]
        result["status"] = "observed"
        if keep_open:
            result["process_left_running"] = True
    except Exception as error:
        result["status"] = "error"
        result["error"] = repr(error)
        result["traceback"] = traceback.format_exc()
        raise
    finally:
        write_json(run_dir / "orbital-entry.json", result)
        if process is not None and not keep_open:
            try:
                send_keys("{ESC}")
                windows = Desktop(backend="win32").windows(
                    process=process.pid, visible_only=True
                )
                main_forms = [w for w in windows if w.class_name() == "TMainForm"]
                if main_forms:
                    choose_primary_window(main_forms).close()
                process.wait(timeout=8)
            except Exception:
                pass
    return run_dir


def audit_exports(executable: Path, fixture: Path, keep_open: bool) -> Path:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    run_dir = REFERENCE_ROOT / stamp
    run_dir.mkdir(parents=True, exist_ok=False)
    copied_fixture = run_dir / fixture.name
    shutil.copy2(fixture, copied_fixture)
    result: dict[str, Any] = {
        "schema": 1,
        "started_at_utc": stamp,
        "command": "exports",
        "fixture_source": str(fixture),
        "fixture_copy": str(copied_fixture.relative_to(PROJECT)),
        "fixture_sha256": sha256(copied_fixture),
        "status": "starting",
    }
    process: subprocess.Popen[Any] | None = None
    try:
        process = subprocess.Popen([str(executable)], cwd=str(executable.parent))
        result["process_id"] = process.pid
        primary = wait_for_primary_window(process.pid)
        result["open"] = open_file_through_dialog(process.pid, primary, copied_fixture)
        uia_window = Desktop(backend="uia").window(handle=primary.handle)
        uia_window.child_window(title="File", control_type="MenuItem").wrapper_object().click_input()
        time.sleep(0.2)
        save_as = find_visible_element(process.pid, "Save as", "MenuItem")
        save_as.click_input()
        time.sleep(0.25)
        save_structure = find_visible_element(
            process.pid,
            "Save structure (as XYZ or XMOL file)\tCtrl+S",
            "MenuItem",
        )
        save_structure.click_input()
        save_dialog = wait_for_secondary_window(process.pid, primary.handle)
        result["structure_save_dialog"] = {
            "title": save_dialog.window_text(),
            "class_name": save_dialog.class_name(),
            "rectangle": _rect_list(save_dialog),
        }
        save_dialog_path = run_dir / "structure-save-dialog.png"
        capture_window_region(save_dialog, save_dialog_path)
        result["structure_save_dialog_screenshot"] = str(
            save_dialog_path.relative_to(PROJECT)
        )
        result["structure_save_dialog_elements"] = _visible_named_elements(
            process.pid
        )
        if save_dialog.class_name() == "TSaveXYZForm":
            options_uia = Desktop(backend="uia").window(handle=save_dialog.handle)
            format_item = options_uia.child_window(
                title="Simple XYZ format (atom types as characters)",
                control_type="ListItem",
            ).wrapper_object()
            format_item.click_input()
            options_uia.child_window(
                title="Save", control_type="Button"
            ).wrapper_object().click_input()
            time.sleep(0.3)
            save_dialog = wait_for_secondary_window(process.pid, primary.handle)
            result["file_save_dialog"] = {
                "title": save_dialog.window_text(),
                "class_name": save_dialog.class_name(),
                "rectangle": _rect_list(save_dialog),
            }
        save_dialog_uia = Desktop(backend="uia").window(handle=save_dialog.handle)
        output_xyz = run_dir / "exported-water.xyz"
        all_filename_edits = [
            edit
            for edit in save_dialog_uia.descendants(control_type="Edit")
            if edit.is_visible() and edit.is_enabled()
        ]
        filename_edits = [
            edit
            for edit in all_filename_edits
            if str(getattr(edit.element_info, "automation_id", "")) == "1148"
        ]
        if not filename_edits and all_filename_edits:
            filename_edits = [
                max(all_filename_edits, key=lambda edit: edit.rectangle().bottom)
            ]
        if not filename_edits:
            raise RuntimeError("Save dialog exposed no file-name edit")
        filename_edits[0].click_input()
        filename_edits[0].set_edit_text(str(output_xyz))
        save_buttons = [
            wrapper
            for wrapper in save_dialog_uia.descendants()
            if wrapper.is_visible()
            and wrapper.is_enabled()
            and str(getattr(wrapper.element_info, "automation_id", "")) == "1"
            and wrapper.window_text().replace("&", "").strip().lower() == "save"
        ]
        if not save_buttons:
            raise RuntimeError("Save dialog exposed no Save button")
        save_buttons[0].click_input()
        deadline = time.monotonic() + 15.0
        while time.monotonic() < deadline and not output_xyz.exists():
            time.sleep(0.2)
        result["structure_export"] = {
            "path": str(output_xyz.relative_to(PROJECT)),
            "exists": output_xyz.exists(),
            "sha256": sha256(output_xyz) if output_xyz.exists() else None,
            "size": output_xyz.stat().st_size if output_xyz.exists() else None,
        }
        primary.set_focus()
        uia_window = Desktop(backend="uia").window(handle=primary.handle)
        image_before = run_dir / "draw-export-before.png"
        capture_window_region(primary, image_before)
        uia_window.child_window(title="View", control_type="MenuItem").wrapper_object().click_input()
        time.sleep(0.2)
        draw_export = find_visible_element(
            process.pid,
            "Draw \"export\" picture (with anti-aliasing)\tCtrl+Q",
            "MenuItem",
        )
        draw_export.click_input()
        time.sleep(0.8)
        image_after = run_dir / "draw-export-after.png"
        capture_window_region(primary, image_after)
        result["draw_export_command"] = {
            "before": str(image_before.relative_to(PROJECT)),
            "after": str(image_after.relative_to(PROJECT)),
            "difference": image_difference(image_before, image_after),
        }
        uia_window.child_window(title="File", control_type="MenuItem").wrapper_object().click_input()
        time.sleep(0.2)
        find_visible_element(process.pid, "Save as", "MenuItem").click_input()
        time.sleep(0.25)
        find_visible_element(process.pid, "Save image", "MenuItem").click_input()
        picture_dialog = wait_for_secondary_window(process.pid, primary.handle)
        time.sleep(0.4)
        result["picture_dialog"] = {
            "title": picture_dialog.window_text(),
            "class_name": picture_dialog.class_name(),
            "rectangle": _rect_list(picture_dialog),
        }
        picture_path = run_dir / "picture-export-dialog.png"
        capture_window_region(picture_dialog, picture_path)
        result["picture_dialog_screenshot"] = str(
            picture_path.relative_to(PROJECT)
        )
        result["picture_dialog_elements"] = _visible_named_elements(process.pid)
        picture_uia = Desktop(backend="uia").window(handle=picture_dialog.handle)
        picture_uia.child_window(
            title="Save", control_type="Button"
        ).wrapper_object().click_input()
        image_file_dialog = None
        deadline = time.monotonic() + 10.0
        while time.monotonic() < deadline:
            candidates = [
                window
                for window in Desktop(backend="win32").windows(
                    process=process.pid, visible_only=True
                )
                if window.handle not in {primary.handle, picture_dialog.handle}
                and window.rectangle().width() > 100
                and window.rectangle().height() > 80
            ]
            if candidates:
                image_file_dialog = choose_primary_window(candidates)
                break
            time.sleep(0.2)
        if image_file_dialog is None:
            raise TimeoutError("Image file Save As dialog did not appear")
        result["image_file_dialog"] = {
            "title": image_file_dialog.window_text(),
            "class_name": image_file_dialog.class_name(),
            "rectangle": _rect_list(image_file_dialog),
        }
        image_file_uia = Desktop(backend="uia").window(handle=image_file_dialog.handle)
        image_output = run_dir / "exported-water.jpg"
        image_edits = [
            edit
            for edit in image_file_uia.descendants(control_type="Edit")
            if edit.is_visible() and edit.is_enabled()
        ]
        if not image_edits:
            raise RuntimeError("Image Save As dialog exposed no file-name edit")
        image_edit = max(image_edits, key=lambda edit: edit.rectangle().bottom)
        image_edit.click_input()
        try:
            image_edit.set_edit_text(str(image_output))
        except Exception as set_text_error:
            result["image_filename_set_fallback"] = repr(set_text_error)
            pyautogui.hotkey("ctrl", "a")
            pyautogui.write(str(image_output), interval=0.001)
        image_save_buttons = [
            wrapper
            for wrapper in image_file_uia.descendants()
            if wrapper.is_visible()
            and wrapper.is_enabled()
            and str(getattr(wrapper.element_info, "automation_id", "")) == "1"
            and wrapper.window_text().replace("&", "").strip().lower() == "save"
        ]
        if not image_save_buttons:
            result["image_save_button_fallback"] = "Enter key"
            pyautogui.press("enter")
        else:
            image_save_buttons[0].click_input()
        deadline = time.monotonic() + 15.0
        while time.monotonic() < deadline and not image_output.exists():
            time.sleep(0.2)
        result["image_export"] = {
            "path": str(image_output.relative_to(PROJECT)),
            "exists": image_output.exists(),
            "sha256": sha256(image_output) if image_output.exists() else None,
            "size": image_output.stat().st_size if image_output.exists() else None,
        }
        result["status"] = "observed"
        if keep_open:
            result["process_left_running"] = True
    except Exception as error:
        result["status"] = "error"
        result["error"] = repr(error)
        result["traceback"] = traceback.format_exc()
        raise
    finally:
        write_json(run_dir / "exports.json", result)
        if process is not None and not keep_open:
            try:
                send_keys("{ESC}")
                windows = Desktop(backend="win32").windows(
                    process=process.pid, visible_only=True
                )
                main_forms = [w for w in windows if w.class_name() == "TMainForm"]
                if main_forms:
                    choose_primary_window(main_forms).close()
                process.wait(timeout=8)
            except Exception:
                pass
    return run_dir


def audit_menus(process_id: int) -> Path:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    run_dir = REFERENCE_ROOT / stamp
    run_dir.mkdir(parents=True, exist_ok=False)
    primary = wait_for_primary_window(process_id)
    primary.set_focus()
    time.sleep(0.5)
    top_menu_names = ["File", "Edit", "View", "Display", "Tools", "Help"]
    result: dict[str, Any] = {
        "schema": 1,
        "started_at_utc": stamp,
        "command": "menus",
        "process_id": process_id,
        "primary_window": primary.window_text(),
        "primary_rectangle": _rect_list(primary),
        "menus": [],
        "status": "starting",
    }
    try:
        uia_window = Desktop(backend="uia").window(handle=primary.handle)
        for index, menu_name in enumerate(top_menu_names):
            send_keys("{ESC}")
            time.sleep(0.15)
            item_result: dict[str, Any] = {"name": menu_name}
            try:
                item = uia_window.child_window(
                    title=menu_name, control_type="MenuItem"
                ).wrapper_object()
                item_result["source_rectangle"] = _rect_list(item)
                item.click_input()
                time.sleep(0.45)
                path = run_dir / f"menu-{index + 1:02d}-{menu_name.lower()}.png"
                capture_window_region(primary, path)
                item_result["screenshot"] = str(path.relative_to(PROJECT))
                item_result["visible_named_elements"] = _visible_named_elements(process_id)
                item_result["visible_windows"] = [
                    {
                        "title": window.window_text(),
                        "class_name": window.class_name(),
                        "rectangle": _rect_list(window),
                    }
                    for window in Desktop(backend="win32").windows(
                        process=process_id, visible_only=True
                    )
                ]
                item_result["status"] = "observed"
            except Exception as error:
                item_result["status"] = "error"
                item_result["error"] = repr(error)
                item_result["traceback"] = traceback.format_exc()
            finally:
                send_keys("{ESC}")
                time.sleep(0.15)
            result["menus"].append(item_result)
        submenu_specs = {
            "File": ["Save as"],
            "Edit": [
                "Operations with all selected atoms",
                "Basic editor options",
                "Operations with vectors and planes",
                "Operations with atomic coordinates",
                "Dragging type",
                "Rotate along selected",
            ],
            "View": ["Toolbars"],
            "Display": ["Mixed"],
            "Tools": [
                "Build Z-matrix",
                "GED tools",
                "Crystallography tools",
                "Create animation",
                "Create section for input file",
                "Orbitals",
                "Structure comparer",
                "Structure combiner",
                "Mass spectrum analysis tools",
                "Simple utilities",
                "Scripts",
                "Supporting...",
                "Utilities for working with custom graphs",
                "Jobs archive",
            ],
        }
        result["submenus"] = []
        submenu_index = 0
        for parent_name, item_names in submenu_specs.items():
            for item_name in item_names:
                submenu_index += 1
                submenu_result: dict[str, Any] = {
                    "parent": parent_name,
                    "item": item_name,
                }
                try:
                    send_keys("{ESC}")
                    parent = uia_window.child_window(
                        title=parent_name, control_type="MenuItem"
                    ).wrapper_object()
                    parent.click_input()
                    time.sleep(0.2)
                    item = find_visible_element(process_id, item_name, "MenuItem")
                    rect = item.rectangle()
                    submenu_result["source_rectangle"] = _rect_list(item)
                    pyautogui.moveTo(
                        (rect.left + rect.right) // 2,
                        (rect.top + rect.bottom) // 2,
                        duration=0.1,
                    )
                    time.sleep(0.45)
                    elements = _visible_named_elements(process_id)
                    submenu_result["menu_items"] = [
                        element
                        for element in elements
                        if element["control_type"] == "MenuItem"
                    ]
                    path = run_dir / f"submenu-{submenu_index:02d}.png"
                    capture_window_region(primary, path)
                    submenu_result["screenshot"] = str(path.relative_to(PROJECT))
                    submenu_result["status"] = "observed"
                except Exception as error:
                    submenu_result["status"] = "error"
                    submenu_result["error"] = repr(error)
                finally:
                    send_keys("{ESC}")
                    time.sleep(0.1)
                result["submenus"].append(submenu_result)
        result["status"] = (
            "observed"
            if all(item["status"] == "observed" for item in result["menus"])
            else "partial"
        )
    finally:
        write_json(run_dir / "menus.json", result)
    return run_dir


def write_json(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False), encoding="utf-8")


def launch_and_inventory(executable: Path, keep_open: bool) -> Path:
    if not executable.is_file():
        raise FileNotFoundError(executable)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    run_dir = REFERENCE_ROOT / stamp
    run_dir.mkdir(parents=True, exist_ok=False)
    log: dict[str, Any] = {
        "schema": 1,
        "started_at_utc": stamp,
        "command": "inventory",
        "executable": str(executable),
        "executable_sha256": sha256(executable),
        "environment": configure_dpi_awareness(),
        "status": "starting",
    }
    process: subprocess.Popen[Any] | None = None
    try:
        process = subprocess.Popen([str(executable)], cwd=str(executable.parent))
        log["process_id"] = process.pid
        windows = wait_for_windows(process.pid)
        primary = choose_primary_window(windows)
        primary.set_focus()
        time.sleep(1.0)
        log["win32"] = enumerate_windows(process.pid, "win32")
        log["uia"] = enumerate_windows(process.pid, "uia")
        log["native_menu"] = inventory_native_menu(primary)
        log["captures"] = capture_images(primary, run_dir)
        log["status"] = "observed"
        log["visible_window_count"] = len(windows)
        log["window_titles"] = [window.window_text() for window in windows]
        if keep_open:
            log["process_left_running"] = True
        else:
            primary.close()
            try:
                process.wait(timeout=8)
            except subprocess.TimeoutExpired:
                log["close_timeout"] = True
    except Exception as error:
        log["status"] = "error"
        log["error"] = repr(error)
        log["traceback"] = traceback.format_exc()
        if process is not None:
            try:
                windows = Desktop(backend="win32").windows(process=process.pid, visible_only=False)
                log["failure_windows"] = [window.window_text() for window in windows]
                if windows:
                    log["captures"] = capture_images(choose_primary_window(windows), run_dir)
            except Exception as capture_error:
                log["failure_capture_error"] = repr(capture_error)
        raise
    finally:
        write_json(run_dir / "run.json", log)
    return run_dir


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "command",
        choices=[
            "inventory",
            "menus",
            "xyz-workflow",
            "orca-navigation",
            "result-tree",
            "measurements",
            "select-all",
            "orbital-entry",
            "exports",
        ],
    )
    parser.add_argument("--exe", type=Path, default=DEFAULT_EXE)
    parser.add_argument("--keep-open", action="store_true")
    parser.add_argument("--pid", type=int)
    parser.add_argument("--fixture", type=Path)
    arguments = parser.parse_args()
    if arguments.command == "inventory":
        run_dir = launch_and_inventory(arguments.exe.resolve(), arguments.keep_open)
    elif arguments.command == "xyz-workflow":
        if arguments.fixture is None:
            parser.error("xyz-workflow requires --fixture")
        run_dir = audit_xyz_workflow(
            arguments.exe.resolve(), arguments.fixture.resolve(), arguments.keep_open
        )
    elif arguments.command == "orca-navigation":
        if arguments.fixture is None:
            parser.error("orca-navigation requires --fixture")
        run_dir = audit_orca_navigation(
            arguments.exe.resolve(), arguments.fixture.resolve(), arguments.keep_open
        )
    elif arguments.command == "result-tree":
        if arguments.fixture is None:
            parser.error("result-tree requires --fixture")
        run_dir = audit_result_tree(
            arguments.exe.resolve(), arguments.fixture.resolve(), arguments.keep_open
        )
    elif arguments.command == "measurements":
        if arguments.fixture is None:
            parser.error("measurements requires --fixture")
        run_dir = audit_measurements(
            arguments.exe.resolve(), arguments.fixture.resolve(), arguments.keep_open
        )
    elif arguments.command == "select-all":
        if arguments.fixture is None:
            parser.error("select-all requires --fixture")
        run_dir = audit_select_all(
            arguments.exe.resolve(), arguments.fixture.resolve(), arguments.keep_open
        )
    elif arguments.command == "orbital-entry":
        if arguments.fixture is None:
            parser.error("orbital-entry requires --fixture")
        run_dir = audit_orbital_entry(
            arguments.exe.resolve(), arguments.fixture.resolve(), arguments.keep_open
        )
    elif arguments.command == "exports":
        if arguments.fixture is None:
            parser.error("exports requires --fixture")
        run_dir = audit_exports(
            arguments.exe.resolve(), arguments.fixture.resolve(), arguments.keep_open
        )
    else:
        process: subprocess.Popen[Any] | None = None
        process_id = arguments.pid
        try:
            if process_id is None:
                executable = arguments.exe.resolve()
                process = subprocess.Popen([str(executable)], cwd=str(executable.parent))
                process_id = process.pid
                wait_for_windows(process_id)
            open_result = None
            fixture_path = None
            if arguments.fixture is not None:
                fixture_path = arguments.fixture.resolve()
                primary = wait_for_primary_window(process_id)
                open_result = open_file_through_dialog(
                    process_id, primary, fixture_path
                )
            run_dir = audit_menus(process_id)
            if fixture_path is not None:
                menu_log_path = run_dir / "menus.json"
                menu_log = json.loads(menu_log_path.read_text(encoding="utf-8"))
                menu_log["loaded_fixture"] = str(fixture_path)
                menu_log["loaded_fixture_sha256"] = sha256(fixture_path)
                menu_log["open"] = open_result
                write_json(menu_log_path, menu_log)
        finally:
            if process is not None and not arguments.keep_open:
                windows = Desktop(backend="win32").windows(
                    process=process.pid, visible_only=True
                )
                if windows:
                    choose_primary_window(windows).close()
                try:
                    process.wait(timeout=8)
                except subprocess.TimeoutExpired:
                    pass
    print(run_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
