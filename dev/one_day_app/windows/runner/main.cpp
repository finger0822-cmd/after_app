#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <iostream>
#include <sstream>
#include <iomanip>
#include <exception>
#include <csignal>

#include "flutter_window.h"
#include "utils.h"

// Terminate handler for C++ exceptions
void AppTerminateHandler() {
  std::wcout << L"[Windows Runner] === TERMINATE HANDLER CALLED ===\n";
  std::wcout << L"[Windows Runner] C++ exception or std::terminate() called\n";
  std::wcout << L"[Windows Runner] ====================================\n";
  std::abort();
}

// Signal handler for SIGABRT, SIGFPE, SIGILL, SIGSEGV, SIGTERM
void AppSignalHandler(int signal) {
  std::wstring signalName;
  switch (signal) {
    case SIGABRT: signalName = L"SIGABRT"; break;
    case SIGFPE: signalName = L"SIGFPE"; break;
    case SIGILL: signalName = L"SIGILL"; break;
    case SIGSEGV: signalName = L"SIGSEGV"; break;
    case SIGTERM: signalName = L"SIGTERM"; break;
    default: signalName = L"UNKNOWN"; break;
  }
  std::wcout << L"[Windows Runner] === SIGNAL HANDLER CALLED ===\n";
  std::wcout << L"[Windows Runner] Signal: " << signalName << L" (" << signal << L")\n";
  std::wcout << L"[Windows Runner] ============================\n";
}

// Unhandled exception handler (captures crashes in Windows runner)
LONG WINAPI AppUnhandledExceptionFilter(EXCEPTION_POINTERS* exception_info) {
  std::wstringstream ss;
  ss << L"[Windows Runner] === UNHANDLED EXCEPTION ===\n";
  ss << L"[Windows Runner] Exception Code: 0x" << std::hex << std::uppercase 
     << exception_info->ExceptionRecord->ExceptionCode << std::dec << L"\n";
  ss << L"[Windows Runner] Exception Address: 0x" << std::hex << std::uppercase
     << reinterpret_cast<uintptr_t>(exception_info->ExceptionRecord->ExceptionAddress) << std::dec << L"\n";
  
  // Output to stdout (visible in flutter run)
  std::wcout << ss.str() << std::flush;
  
  // If debugger is attached, pass to debugger
  if (::IsDebuggerPresent()) {
    return EXCEPTION_CONTINUE_SEARCH;
  }
  
  // If no debugger, indicate exception was handled
  return EXCEPTION_EXECUTE_HANDLER;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Set terminate handler for C++ exceptions
  std::set_terminate(AppTerminateHandler);
  
  // Set signal handlers
  std::signal(SIGABRT, AppSignalHandler);
  std::signal(SIGFPE, AppSignalHandler);
  std::signal(SIGILL, AppSignalHandler);
  std::signal(SIGSEGV, AppSignalHandler);
  std::signal(SIGTERM, AppSignalHandler);
  
  // Set unhandled exception handler (SEH)
  ::SetUnhandledExceptionFilter(AppUnhandledExceptionFilter);
  
  // Output startup log to stdout
  std::wcout << L"[Windows Runner] === START ===\n";
  std::wcout << L"[Windows Runner] Instance: 0x" << std::hex << std::uppercase 
             << reinterpret_cast<uintptr_t>(instance) << std::dec << L"\n";
  std::wcout << L"[Windows Runner] Command Line: " << command_line << L"\n";
  
  try {
    // Attach to console when present (e.g., 'flutter run') or create a
    // new console when running with a debugger.
    if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
      CreateAndAttachConsole();
    }

    // Initialize COM, so that it is available for use in the library and/or
    // plugins.
    ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    std::wcout << L"[Windows Runner] COM initialized\n";

    flutter::DartProject project(L"data");
    std::wcout << L"[Windows Runner] DartProject created\n";

    std::vector<std::string> command_line_arguments =
        GetCommandLineArguments();

    project.set_dart_entrypoint_arguments(std::move(command_line_arguments));
    std::wcout << L"[Windows Runner] Dart entrypoint arguments set\n";

    FlutterWindow window(project);
    Win32Window::Point origin(10, 10);
    Win32Window::Size size(1280, 720);
    
    std::wcout << L"[Windows Runner] Creating window...\n";
    if (!window.Create(L"One Day", origin, size)) {
      std::wcout << L"[Windows Runner] Window creation FAILED\n";
      return EXIT_FAILURE;
    }
    std::wcout << L"[Windows Runner] Window created successfully\n";
    
    window.SetQuitOnClose(true);

    std::wcout << L"[Windows Runner] Entering message loop...\n";
    ::MSG msg;
    while (::GetMessage(&msg, nullptr, 0, 0)) {
      ::TranslateMessage(&msg);
      ::DispatchMessage(&msg);
    }

    std::wcout << L"[Windows Runner] Message loop exited\n";
    ::CoUninitialize();
    std::wcout << L"[Windows Runner] === EXIT SUCCESS ===\n";
    return EXIT_SUCCESS;
  } catch (const std::exception& e) {
    std::wcout << L"[Windows Runner] === C++ EXCEPTION ===\n";
    std::wcout << L"[Windows Runner] Exception: " << e.what() << L"\n";
    std::wcout << L"[Windows Runner] ====================\n";
    return EXIT_FAILURE;
  } catch (...) {
    std::wcout << L"[Windows Runner] === UNKNOWN EXCEPTION ===\n";
    std::wcout << L"[Windows Runner] ========================\n";
    return EXIT_FAILURE;
  }
}
