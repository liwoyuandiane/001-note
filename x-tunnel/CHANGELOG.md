# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.2.0] - 2025-01-28

### Added
- .env file support for loading environment variables
- `load_env_file()` function to load environment variables from .env file
- `-e` command-line option to load configuration from .env file
- `.env.example` template file with detailed configuration documentation
- Comprehensive .env configuration section in README
- 7 new FAQ entries covering .env file usage
- `.gitignore` file to protect sensitive configuration files

### Changed
- Improved code structure and maintainability
- Enhanced error handling with better user feedback
- Updated README with complete .env configuration guide
- Added MIT license with full license text
- Expanded contributing guidelines with detailed instructions
- Improved documentation quality and organization

### Fixed
- Minor improvements to configuration handling

## [3.1.0] - 2024-12-XX

### Changed
- Improved error handling: Added detailed error messages for all API calls
- Optimized JSON parsing: Enhanced data extraction logic with additional error checks
- Added DNS conflict detection: Check for existing DNS records before creating new ones
- Added curl timeout protection: Set 30-second timeout for all API calls
- Fixed variable scope issues: remove_all function now correctly handles load_tunnel_info return values
- Optimized API response parsing: Extract data from result field for better reliability
- Enhanced security: Remove whitespace from JSON field values to avoid parsing errors

## [3.0.0] - 2024-11-XX

### Added
- API auto-creation tunnel mode for fully automated tunnel management
- Cloudflare API support for creating tunnels, configuring ingress, and binding domains
- Tunnel information persistence (.tunnel_info file)
- Support for automatic cleanup of API-created remote resources (DNS records, tunnels)
- New command-line parameters: -d (domain), -n (tunnel name)
- Extended remove command to support cleaning API-created resources
- Interactive menu now includes API auto-creation mode option
- Comprehensive documentation with API mode usage guide and FAQ

### Changed
- Major restructure of installation and tunnel creation workflows
- Enhanced configuration management with support for multiple modes

## [2.0.0] - 2024-10-XX

### Added
- Command-line parameter mode support
- Status viewing functionality
- Improved error handling and log output
- Help documentation
- Improved code structure and maintainability

## [1.0.0] - 2024-09-XX

### Added
- Initial release
- Interactive menu support
- Basic tunnel functionality

[3.2.0]: https://github.com/your-username/x-tunnel/compare/v3.1.0...v3.2.0
[3.1.0]: https://github.com/your-username/x-tunnel/compare/v3.0.0...v3.1.0
[3.0.0]: https://github.com/your-username/x-tunnel/compare/v2.0.0...v3.0.0
[2.0.0]: https://github.com/your-username/x-tunnel/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/your-username/x-tunnel/releases/tag/v1.0.0
