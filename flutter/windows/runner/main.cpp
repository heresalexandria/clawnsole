#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

// Names the mutex that marks a running Clawnsole in the current session, so a
// second launch hands off to that instance instead of opening another window.
constexpr const wchar_t kSingleInstanceMutexName[] =
    L"Local\\ClawnsoleSingleInstance";

// Title of the top-level window; with the Win32Window class name it identifies
// the running instance's window.
constexpr const wchar_t kWindowTitle[] = L"Clawnsole";

// Initial client area in logical pixels. Win32Window centers the window on
// the primary monitor and shrinks it to fit a smaller work area.
constexpr unsigned int kInitialWidth = 1280;
constexpr unsigned int kInitialHeight = 720;

// Smallest client area in logical pixels, matching the Electron shell's
// 1040x700 floor.
constexpr unsigned int kMinimumWidth = 1040;
constexpr unsigned int kMinimumHeight = 700;

// Brings the already running instance's window to the front.
void ActivateRunningInstance() {
  HWND window = ::FindWindow(Win32Window::GetWindowClassName(), kWindowTitle);
  if (window == nullptr) {
    return;
  }
  if (::IsIconic(window)) {
    ::ShowWindow(window, SW_RESTORE);
  }
  ::SetForegroundWindow(window);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Only one Clawnsole runs per session. CreateMutex hands back a handle to
  // the existing mutex and reports ERROR_ALREADY_EXISTS when this session
  // already has one. Any other failure leaves the handle null and starts
  // normally: a second window is a far better outcome than refusing to launch,
  // and a mutex owned by a different user carries no claim on this one.
  HANDLE single_instance_mutex =
      ::CreateMutex(nullptr, FALSE, kSingleInstanceMutexName);
  const DWORD mutex_status = ::GetLastError();
  if (single_instance_mutex != nullptr &&
      mutex_status == ERROR_ALREADY_EXISTS) {
    ActivateRunningInstance();
    ::CloseHandle(single_instance_mutex);
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  window.SetMinimumSize(Win32Window::Size(kMinimumWidth, kMinimumHeight));
  Win32Window::Size size(kInitialWidth, kInitialHeight);
  if (!window.Create(kWindowTitle, size)) {
    if (single_instance_mutex != nullptr) {
      ::CloseHandle(single_instance_mutex);
    }
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (single_instance_mutex != nullptr) {
    ::CloseHandle(single_instance_mutex);
  }
  return EXIT_SUCCESS;
}
