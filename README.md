# COMMUNITI

COMMUNITI is a community wellbeing mobile application designed to enhance community engagement and safety. The app features two core functionalities: **HALO** (anonymous community recognition) and **SafeWalk** (community safety map). 

## Features

- **HALO**: A platform for users to recognize and appreciate acts of kindness within their community anonymously. Users can give and receive HALOs, contributing to a positive community atmosphere.
  
- **SafeWalk**: A safety map that allows users to report incidents and view safe spots in their area. This feature aims to enhance community safety by providing real-time information about incidents and safe locations.

## Project Structure

The project is organized into several directories, each serving a specific purpose:

- **lib**: Contains the main application code.
  - **core**: Holds theme-related files, constants, and utility functions.
  - **models**: Defines data models used throughout the app.
  - **services**: Contains service classes for Firebase and other functionalities.
  - **providers**: Manages state using the Provider package.
  - **widgets**: Contains reusable UI components.
  - **screens**: Holds the various screens of the app, including authentication, feed, halo, search, safewalk, and profile.

## Dependencies

The project utilizes several dependencies to enhance functionality and user experience, including:

- Firebase for backend services (authentication, Firestore, etc.)
- Google Maps for the SafeWalk feature
- Provider for state management
- Google Fonts for typography
- Lucide Icons for custom icons

## Getting Started

To get started with the COMMUNITI app, clone the repository and run the following commands:

```bash
flutter pub get
```

Then, run the app on your preferred device:

```bash
flutter run
```

## Contribution

Contributions are welcome! Please feel free to submit a pull request or open an issue for any suggestions or improvements.

## License

This project is licensed under the MIT License. See the LICENSE file for more details.