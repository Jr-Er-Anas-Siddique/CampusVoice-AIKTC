# 📢 CampusVoice AIKTC

A **Flutter + Firebase-based campus complaint management system** that allows students to report issues, track progress, and interact with the campus community, while enabling committees to efficiently manage and resolve complaints.

---

## 🚀 Features

### 👨‍🎓 Student Features

* 📌 Submit complaints with images/videos
* 📍 GPS validation for infrastructure issues
* 📝 Save complaints as drafts
* 👍 Support (upvote) complaints
* 💬 Comment on complaints
* 📊 Track complaint status with timeline
* 📄 Generate & share PDF reports
* ⚠️ Challenge resolved complaints

### 🏛️ Committee Features

* 📋 Dedicated dashboard
* 🛠️ Manage assigned complaints
* 🔄 Update complaint status
* 🧾 Add resolution notes and media

### 🤖 Smart Features

* 🛡️ AI-based auto moderation (8 checks)
* 🔁 Duplicate complaint detection
* 🔒 Auto privacy for sensitive issues
* ⚡ Real-time updates using Firestore

---

## 🏗️ Project Structure

```
lib/
│
├── config/        # Static configurations  
├── models/        # Data models  
├── services/      # Business logic  
├── features/      # UI (screens/pages)  
└── core/utils/    # Utilities  
```

---

## 🧰 Tech Stack

* **Frontend:** Flutter
* **Backend:** Firebase (Auth + Firestore)
* **Storage:** Cloudinary
* **Local Storage:** SharedPreferences

---

## 🔄 Complaint Lifecycle

```
Draft → Pending Review → Approved → Under Review → In Progress → Resolved / Rejected  
                        ↘ Flagged (hidden)
```

---

## ⚙️ Setup Instructions

### 1. Clone Repository

```bash
git clone https://github.com/your-username/campusvoice.git
cd campusvoice
```

### 2. Install Dependencies

```bash
flutter pub get
```

### 3. Firebase Setup

* Create Firebase project
* Enable Authentication (Email/Password)
* Enable Firestore Database
* Add config files:

  * google-services.json (Android)
  * GoogleService-Info.plist (iOS)

### 4. Cloudinary Setup

* Create Cloudinary account
* Create unsigned upload preset
* Configure credentials in cloudinary_service.dart

### 5. Run the App

```bash
flutter run
```

---

## 🔐 Authentication Rules

* Only **AIKTC student emails** allowed
  Example: [22dco06@aiktc.ac.in](mailto:22dco06@aiktc.ac.in)

* Students → Direct access

* Faculty → Must be whitelisted in Firestore

---

## 📊 Firestore Structure

```
users/
committee_members/
complaints/
    ├── comments/
    └── supporters/
```

---

## 📦 Key Components

### Models

* PostModel
* CommentModel
* CommitteeMember

### Services

* AuthService
* PostService
* ModerationService
* SocialService
* CloudinaryService
* PdfService

---

## 🧠 Concepts Used

* Reactive Programming (Streams)
* Firestore Transactions
* Singleton Pattern
* Facade Pattern
* Immutable Data Models
* GPS Boundary Validation (Ray Casting Algorithm)

---

## 🛠️ Future Improvements

* 🔔 Push notifications
* 🌐 Admin web dashboard
* 🤖 Advanced AI moderation
* 📈 Analytics system

---

## 👨‍💻 Author

Roll No: 22DCO06

---

## 📜 License

This project is developed for academic purposes.
