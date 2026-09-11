#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <shlobj.h>
#include <windows.h>

#include <filesystem>

#include "flutter_window.h"
#include "utils.h"

namespace {

class SingleInstanceLock {
 public:
  enum class Result { kAcquired, kAlreadyRunning, kError };

  SingleInstanceLock() = default;
  ~SingleInstanceLock() {
    if (handle_ != INVALID_HANDLE_VALUE) {
      ::CloseHandle(handle_);
    }
  }

  SingleInstanceLock(const SingleInstanceLock&) = delete;
  SingleInstanceLock& operator=(const SingleInstanceLock&) = delete;

  Result Acquire() {
    PWSTR local_app_data = nullptr;
    if (FAILED(::SHGetKnownFolderPath(FOLDERID_LocalAppData, KF_FLAG_CREATE,
                                      nullptr, &local_app_data))) {
      return Result::kError;
    }

    const std::filesystem::path lock_directory =
        std::filesystem::path(local_app_data) /
        L"com.wcashwallet.warden.testnet";
    ::CoTaskMemFree(local_app_data);

    std::error_code error;
    std::filesystem::create_directories(lock_directory, error);
    if (error) {
      return Result::kError;
    }

    const std::filesystem::path lock_path = lock_directory / L"instance.lock";
    handle_ = ::CreateFileW(lock_path.c_str(), GENERIC_READ | GENERIC_WRITE,
                            0, nullptr, OPEN_ALWAYS,
                            FILE_ATTRIBUTE_HIDDEN, nullptr);
    if (handle_ != INVALID_HANDLE_VALUE) {
      return Result::kAcquired;
    }
    const DWORD open_error = ::GetLastError();
    if (open_error == ERROR_SHARING_VIOLATION ||
        open_error == ERROR_LOCK_VIOLATION) {
      return Result::kAlreadyRunning;
    }
    return Result::kError;
  }

 private:
  HANDLE handle_ = INVALID_HANDLE_VALUE;
};

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // The Windows secure-store backend updates one encrypted map. Holding this
  // exclusive, crash-releasing file handle for the process lifetime prevents
  // stale load-modify-save races between two Warden instances.
  SingleInstanceLock instance_lock;
  const SingleInstanceLock::Result lock_result = instance_lock.Acquire();
  if (lock_result != SingleInstanceLock::Result::kAcquired) {
    ::CoUninitialize();
    return lock_result == SingleInstanceLock::Result::kAlreadyRunning
               ? EXIT_SUCCESS
               : EXIT_FAILURE;
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Wcash Warden Testnet", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
