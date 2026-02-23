import SwiftUI
import MapKit
import CoreLocation
import UIKit

struct CafeMapView: UIViewRepresentable {
    let cafes: [SunnyCafe]
    @Binding var selectedCafe: SunnyCafe?
    @Binding var region: MKCoordinateRegion
    let locateRequestID: Int
    let use3DMap: Bool
    let effectiveCloudCover: Double
    let showCloudOverlay: Bool
    let isNightMode: Bool
    let sunsetTransitionProgress: Double
    let warningMessage: String?
    var onRegionChanged: (MKCoordinateRegion) -> Void
    var onSelectCafe: (SunnyCafe) -> Void
    var onPermissionDenied: () -> Void
    var onUserLocationUpdate: (CLLocationCoordinate2D) -> Void
    var onMapTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.preferredConfiguration = configuration(for3D: use3DMap)
        context.coordinator.mapView = mapView
        context.coordinator.last3DState = use3DMap
        mapView.delegate = context.coordinator
        mapView.register(UserLocationAnnotationView.self, forAnnotationViewWithReuseIdentifier: UserLocationAnnotationView.reuseIdentifier)
        mapView.register(CafeAnnotationView.self, forAnnotationViewWithReuseIdentifier: CafeAnnotationView.reuseIdentifier)
        mapView.register(CafeClusterAnnotationView.self, forAnnotationViewWithReuseIdentifier: CafeClusterAnnotationView.reuseIdentifier)
        let tapRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMapTap(_:)))
        tapRecognizer.cancelsTouchesInView = false
        tapRecognizer.delegate = context.coordinator
        mapView.addGestureRecognizer(tapRecognizer)
        applyBaseMapStyle(to: mapView)
        mapView.isPitchEnabled = use3DMap
        mapView.setRegion(region, animated: false)
        context.coordinator.applyAnnotations(to: mapView, cafes: cafes, around: region)
        context.coordinator.updateCloudOverlay(on: mapView)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self
        let renderRegion = mapView.region.approximatelyEquals(region) ? mapView.region : region
        context.coordinator.applyAnnotations(to: mapView, cafes: cafes, around: renderRegion)

        if locateRequestID != context.coordinator.lastLocateRequestID {
            context.coordinator.lastLocateRequestID = locateRequestID
            context.coordinator.centerOnUser(in: mapView)
        }

        if context.coordinator.last3DState != use3DMap {
            context.coordinator.last3DState = use3DMap
            mapView.preferredConfiguration = configuration(for3D: use3DMap)
            mapView.isPitchEnabled = use3DMap
        }
        applyBaseMapStyle(to: mapView)
        context.coordinator.updateCloudOverlay(on: mapView)

        if !mapView.region.approximatelyEquals(region) {
            context.coordinator.isProgrammaticRegionChange = true
            mapView.setRegion(region, animated: true)
        }

        if let selectedCafe,
           let annotation = context.coordinator.annotationsByID[selectedCafe.id],
           ((mapView.selectedAnnotations.first as? CafePointAnnotation)?.id != selectedCafe.id) {
            mapView.selectAnnotation(annotation, animated: true)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate, CLLocationManagerDelegate, UIGestureRecognizerDelegate {
        var parent: CafeMapView
        weak var mapView: MKMapView?
        var annotationsByID: [String: CafePointAnnotation] = [:]
        var isProgrammaticRegionChange = false
        var lastLocateRequestID: Int = -1
        var last3DState = false
        var cloudOverlay: MKPolygon?
        var cloudOverlayRenderer: MKPolygonRenderer?

        private let locationManager = CLLocationManager()
        private var lastLocationRequestAt: Date?

        init(parent: CafeMapView) {
            self.parent = parent
            super.init()
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        }

        func applyAnnotations(to mapView: MKMapView, cafes: [SunnyCafe], around region: MKCoordinateRegion) {
            let visibleCafes = cafesNear(region: region, within: cafes)
            let incomingIDs = Set(visibleCafes.map(\.id))
            var toRemove: [CafePointAnnotation] = []
            let userCoordinate = mapView.userLocation.location?.coordinate
            let isDimmed = parent.warningMessage != nil || parent.isNightMode || parent.sunsetTransitionProgress > 0

            for (id, existing) in annotationsByID where !incomingIDs.contains(id) {
                toRemove.append(existing)
                annotationsByID.removeValue(forKey: id)
            }
            if !toRemove.isEmpty {
                mapView.removeAnnotations(toRemove)
            }

            var toAdd: [CafePointAnnotation] = []
            for cafe in visibleCafes {
                let distance = cafe.distanceMeters(from: userCoordinate)
                let condition = cafe.effectiveCondition(
                    at: Date(),
                    cloudCover: cafe.cloudCoverPct ?? parent.effectiveCloudCover
                )
                if let existing = annotationsByID[cafe.id] {
                    existing.update(with: cafe, condition: condition, distanceMeters: distance)
                    if let view = mapView.view(for: existing) as? CafeAnnotationView {
                        view.apply(cafe: cafe, condition: condition, isDimmed: isDimmed)
                    }
                } else {
                    let annotation = CafePointAnnotation(cafe: cafe, condition: condition, distanceMeters: distance)
                    annotationsByID[cafe.id] = annotation
                    toAdd.append(annotation)
                }
            }

            if !toAdd.isEmpty {
                mapView.addAnnotations(toAdd)
            }
        }

        private func cafesNear(region: MKCoordinateRegion, within cafes: [SunnyCafe]) -> [SunnyCafe] {
            // Keep a small buffer around the viewport so panning feels smooth without rendering the full dataset.
            let latitudeBuffer = max(region.span.latitudeDelta * 0.8, 0.01)
            let longitudeBuffer = max(region.span.longitudeDelta * 0.8, 0.01)

            let minLat = region.center.latitude - (region.span.latitudeDelta * 0.5) - latitudeBuffer
            let maxLat = region.center.latitude + (region.span.latitudeDelta * 0.5) + latitudeBuffer
            let minLon = region.center.longitude - (region.span.longitudeDelta * 0.5) - longitudeBuffer
            let maxLon = region.center.longitude + (region.span.longitudeDelta * 0.5) + longitudeBuffer

            return cafes.filter {
                let coordinate = $0.coordinate
                return coordinate.latitude >= minLat && coordinate.latitude <= maxLat &&
                    coordinate.longitude >= minLon && coordinate.longitude <= maxLon
            }
        }

        func centerOnUser(in mapView: MKMapView) {
            switch locationManager.authorizationStatus {
            case .notDetermined:
                locationManager.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorizedWhenInUse:
                if let location = mapView.userLocation.location {
                    let region = MKCoordinateRegion(
                        center: location.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    )
                    isProgrammaticRegionChange = true
                    mapView.setRegion(region, animated: true)
                } else {
                    requestLocationIfNeeded()
                }
            case .denied, .restricted:
                DispatchQueue.main.async { self.parent.onPermissionDenied() }
            @unknown default:
                break
            }
        }

        private func requestLocationIfNeeded() {
            let now = Date()
            if let last = lastLocationRequestAt, now.timeIntervalSince(last) < 1.0 {
                return
            }
            lastLocationRequestAt = now
            locationManager.requestLocation()
        }

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
                requestLocationIfNeeded()
            }
        }

        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            guard let mapView, let location = locations.last else { return }
            DispatchQueue.main.async {
                self.parent.onUserLocationUpdate(location.coordinate)
            }
            let newRegion = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
            isProgrammaticRegionChange = true
            mapView.setRegion(newRegion, animated: true)
        }

        func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            _ = error
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: UserLocationAnnotationView.reuseIdentifier,
                    for: annotation
                ) as! UserLocationAnnotationView
                return view
            }

            if let cluster = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: CafeClusterAnnotationView.reuseIdentifier,
                    for: cluster
                ) as! CafeClusterAnnotationView
                view.configure(count: cluster.memberAnnotations.count)
                return view
            }

            guard let cafeAnnotation = annotation as? CafePointAnnotation else {
                return nil
            }

            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: CafeAnnotationView.reuseIdentifier,
                for: cafeAnnotation
            ) as! CafeAnnotationView
            let condition = cafeAnnotation.condition
            view.apply(
                cafe: cafeAnnotation.cafe,
                condition: condition,
                isDimmed: parent.warningMessage != nil || parent.isNightMode || parent.sunsetTransitionProgress > 0
            )
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let cluster = view.annotation as? MKClusterAnnotation {
                let rect = cluster.memberAnnotations.reduce(MKMapRect.null) { partial, ann in
                    partial.union(MKMapRect(origin: MKMapPoint(ann.coordinate), size: MKMapSize(width: 0, height: 0)))
                }
                mapView.setVisibleMapRect(
                    rect,
                    edgePadding: UIEdgeInsets(top: 80, left: 40, bottom: 80, right: 40),
                    animated: true
                )
                return
            }

            guard let cafeAnnotation = view.annotation as? CafePointAnnotation else {
                return
            }
            parent.onSelectCafe(cafeAnnotation.cafe)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polygon = overlay as? MKPolygon else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolygonRenderer(polygon: polygon)
            renderer.strokeColor = .clear
            renderer.lineWidth = 0
            renderer.fillColor = cloudOverlayFillColor(in: mapView)
            cloudOverlayRenderer = renderer
            return renderer
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            updateCloudOverlay(on: mapView)
            applyAnnotations(to: mapView, cafes: parent.cafes, around: mapView.region)

            let region = mapView.region
            let wasProgrammatic = isProgrammaticRegionChange
            isProgrammaticRegionChange = false

            DispatchQueue.main.async {
                self.parent.region = region
                self.parent.onRegionChanged(region)
            }

            if wasProgrammatic {
                return
            }
        }

        @objc func handleMapTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            DispatchQueue.main.async {
                self.parent.onMapTap()
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        func updateCloudOverlay(on mapView: MKMapView) {
            let shouldShow = parent.showCloudOverlay
            guard shouldShow else {
                removeCloudOverlay(from: mapView)
                return
            }

            if cloudOverlay == nil {
                let polygon = worldBoundsPolygon()
                cloudOverlay = polygon
                mapView.addOverlay(polygon, level: .aboveLabels)
            }

            if let renderer = cloudOverlayRenderer {
                renderer.fillColor = cloudOverlayFillColor(in: mapView)
                renderer.setNeedsDisplay()
            }
        }

        private func removeCloudOverlay(from mapView: MKMapView) {
            if let overlay = cloudOverlay {
                mapView.removeOverlay(overlay)
            }
            cloudOverlay = nil
            cloudOverlayRenderer = nil
        }

        private func cloudOverlayFillColor(in mapView: MKMapView) -> UIColor {
            let cloudAlpha = max(0.0, min((parent.effectiveCloudCover / 100.0) * 0.8, 0.58))
            let sunsetProgress = max(0.0, min(parent.sunsetTransitionProgress, 1.0))
            let baselineAlpha: Double
            if parent.isNightMode {
                baselineAlpha = 0.36
            } else if sunsetProgress > 0 {
                baselineAlpha = 0.14 + (sunsetProgress * 0.14)
            } else if parent.warningMessage != nil {
                baselineAlpha = 0.2
            } else {
                baselineAlpha = 0.0
            }
            let alpha = max(cloudAlpha, baselineAlpha)
            let isDarkMode = mapView.traitCollection.userInterfaceStyle == .dark
            let base: UIColor
            if parent.isNightMode {
                base = isDarkMode
                    ? UIColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 1.0)
                    : UIColor(red: 0.34, green: 0.36, blue: 0.43, alpha: 1.0)
            } else if sunsetProgress > 0 {
                let sunsetLight = UIColor(red: 0.75, green: 0.49, blue: 0.30, alpha: 1.0)
                let sunsetDark = UIColor(red: 0.35, green: 0.22, blue: 0.15, alpha: 1.0)
                base = isDarkMode ? sunsetDark : sunsetLight
            } else {
                base = isDarkMode
                    ? UIColor(white: 0.12, alpha: 1.0)
                    : UIColor(white: 0.48, alpha: 1.0)
            }
            return base.withAlphaComponent(alpha)
        }

        private func worldBoundsPolygon() -> MKPolygon {
            // Keep it slightly inside the poles to avoid projection artifacts.
            var coordinates = [
                CLLocationCoordinate2D(latitude: 85.0, longitude: -180.0),
                CLLocationCoordinate2D(latitude: 85.0, longitude: 180.0),
                CLLocationCoordinate2D(latitude: -85.0, longitude: 180.0),
                CLLocationCoordinate2D(latitude: -85.0, longitude: -180.0),
            ]
            return MKPolygon(coordinates: &coordinates, count: coordinates.count)
        }
    }
}

private extension CafeMapView {
    func configuration(for3D: Bool) -> MKMapConfiguration {
        if for3D {
            let config = MKHybridMapConfiguration(elevationStyle: .realistic)
            config.pointOfInterestFilter = .excludingAll
            config.showsTraffic = false
            return config
        }
        let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        config.pointOfInterestFilter = .excludingAll
        config.showsTraffic = false
        return config
    }

    func applyBaseMapStyle(to mapView: MKMapView) {
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsUserLocation = true
        mapView.showsBuildings = false
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.showsTraffic = false
    }
}

final class UserLocationAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "UserLocationAnnotationView"

    private let symbolView = UIImageView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 34, height: 34)
        bounds = frame
        backgroundColor = .systemBlue
        layer.cornerRadius = 17
        layer.borderWidth = 2.5
        layer.borderColor = UIColor.white.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.28
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 2)

        symbolView.translatesAutoresizingMaskIntoConstraints = false
        symbolView.image = UIImage(
            systemName: "person.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)
        )?.withRenderingMode(.alwaysTemplate)
        symbolView.tintColor = .white
        symbolView.contentMode = .scaleAspectFit
        addSubview(symbolView)
        NSLayoutConstraint.activate([
            symbolView.centerXAnchor.constraint(equalTo: centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: centerYAnchor),
            symbolView.widthAnchor.constraint(equalToConstant: 16),
            symbolView.heightAnchor.constraint(equalToConstant: 16),
        ])

        centerOffset = CGPoint(x: 0, y: 0)
        displayPriority = .required
        clusteringIdentifier = nil
        canShowCallout = false
        isAccessibilityElement = true
        accessibilityLabel = "Your location"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class CafePointAnnotation: NSObject, MKAnnotation {
    let id: String
    private(set) var cafe: SunnyCafe
    private(set) var condition: EffectiveCondition
    dynamic var coordinate: CLLocationCoordinate2D

    init(cafe: SunnyCafe, condition: EffectiveCondition, distanceMeters: CLLocationDistance?) {
        self.id = cafe.id
        self.cafe = cafe
        self.condition = condition
        self.coordinate = cafe.coordinate
        super.init()
        _ = distanceMeters
    }

    func update(with cafe: SunnyCafe, condition: EffectiveCondition, distanceMeters: CLLocationDistance?) {
        self.cafe = cafe
        self.condition = condition
        self.coordinate = cafe.coordinate
        _ = distanceMeters
    }
}

final class CafeAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "CafeAnnotationView"

    private let bubbleView = UIView()
    private let symbolView = UIImageView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        clusteringIdentifier = "sunny-cafe"
        collisionMode = .circle
        displayPriority = .defaultHigh
        canShowCallout = false

        frame = CGRect(x: 0, y: 0, width: 26, height: 26)
        bounds = frame
        centerOffset = CGPoint(x: 0, y: 0)

        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.layer.cornerRadius = 13
        bubbleView.layer.masksToBounds = false
        addSubview(bubbleView)

        symbolView.translatesAutoresizingMaskIntoConstraints = false
        symbolView.image = UIImage(
            systemName: "cup.and.saucer.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        )?.withRenderingMode(.alwaysTemplate)
        symbolView.tintColor = .white
        symbolView.contentMode = .scaleAspectFit
        bubbleView.addSubview(symbolView)

        NSLayoutConstraint.activate([
            bubbleView.centerXAnchor.constraint(equalTo: centerXAnchor),
            bubbleView.centerYAnchor.constraint(equalTo: centerYAnchor),
            bubbleView.widthAnchor.constraint(equalToConstant: 26),
            bubbleView.heightAnchor.constraint(equalToConstant: 26),

            symbolView.centerXAnchor.constraint(equalTo: bubbleView.centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: bubbleView.centerYAnchor),
            symbolView.widthAnchor.constraint(equalToConstant: 16),
            symbolView.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(cafe: SunnyCafe, condition: EffectiveCondition, isDimmed: Bool) {
        bubbleView.backgroundColor = UIColor(condition.color)
        bubbleView.layer.cornerRadius = 13
        bubbleView.layer.borderWidth = 1.1
        bubbleView.layer.borderColor = UIColor.white.withAlphaComponent(0.32).cgColor
        bubbleView.layer.shadowColor = UIColor.black.cgColor
        bubbleView.layer.shadowOpacity = isSelected ? 0.26 : 0.18
        bubbleView.layer.shadowRadius = isSelected ? 3 : 2
        bubbleView.layer.shadowOffset = CGSize(width: 0, height: 1)

        alpha = isSelected ? 1.0 : (isDimmed ? 0.58 : 0.92)

        isAccessibilityElement = true
        accessibilityLabel = "\(cafe.name), \(condition.rawValue) adjusted for weather, score \(Int(cafe.sunnyScore))"
        accessibilityHint = "Double tap for quick info, then open details."
    }
}

final class CafeClusterAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "CafeClusterAnnotationView"

    private let label = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 38, height: 38)
        layer.cornerRadius = 19
        layer.backgroundColor = UIColor.black.withAlphaComponent(0.64).cgColor
        layer.borderWidth = 1.5
        layer.borderColor = UIColor.white.withAlphaComponent(0.85).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 3

        label.frame = bounds
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        label.textColor = .white
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOpacity = 0.45
        label.layer.shadowOffset = CGSize(width: 0, height: 1)
        label.layer.shadowRadius = 1
        addSubview(label)

        isAccessibilityElement = true
        accessibilityHint = "Double tap to zoom into this cluster."
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(count: Int) {
        label.text = "\(count)"
        accessibilityLabel = "\(count) cafes clustered"
    }
}
