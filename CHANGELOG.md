# Changelog

All notable changes to AgentForge will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.1] - 2025-03-27
### Changed
- Improved code quality and readability throughout the codebase
- Reduced nested code in flow.ex, runtime.ex, primitives.ex, and tools.ex
- Converted explicit try blocks to implicit try patterns
- Removed trailing whitespace throughout codebase
- Extracted helper functions to improve readability and reduce complexity

## [0.2.0] - 2025-03-26
### Added
- Plugin system with formal plugin behavior interface
- Central plugin manager for plugin lifecycle management
- Tools registry for dynamic tool discovery and registration
- Notification system with channel support
- Built-in HTTP plugin as reference implementation
- Comprehensive example (WeatherPlugin) demonstrating plugin functionality
- Documentation for the plugin system

## [0.1.1] - 2025-03-26
### Added
- Implement Time-Based Flow Limits for Signal Processing
- Add Execution Limits and Statistics Tracking

## [0.1.0] - 2025-03-23
### Added
- Initial release
- Core signal-driven framework
- Store implementation for state management
- Flow composition utilities
- Primitive system implementation
  - Branch primitive
  - Transform primitive
  - Loop primitive
  - Sequence primitive
  - Wait primitive
  - Notify primitive
- Configuration-based workflow definition (YAML/JSON)
- Dynamic flow selection and composition
- Tool registry for extensible command execution
- Comprehensive documentation and examples

[Unreleased]: https://github.com/USERNAME/agent_forge/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/USERNAME/agent_forge/releases/tag/v0.1.0
