import SwiftUI
import MapKit
import CoreLocation

struct CafeMapView: UIViewRepresentable {
    let cafes: [SunnyCafe]
    @Binding var selectedCafe: SunnyCafe?
    @Binding var region: MKCoordinateRegion
    let locateRequestID: Int
    var onRegionChanged: (MKCoordinateRegion) -> Void
    var onSelectCafe: (SunnyCafe) -> Void
    var onPermissionDenied: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        context.coordinator.mapView = mapView
        mapView.delegate = context.coordinator
        mapView.register(CafeAnnotationView.self, forAnnotationViewWithReuseIdentifier: CafeAnnotationView.reuseIdentifier)
        mapView.register(CafeClusterAnnotationView.self, forAnnotationViewWithReuseIdentifier: CafeClusterAnnotationView.reuseIdentifier)
        mapView.showsUserLocation = true
        mapView.pointOfInterestFilter = .excludingAll
        mapView.setRegion(region, animated: false)
        context.coordinator.applyAnnotations(to: mapView, cafes: cafes)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyAnnotations(to: mapView, cafes: cafes)

        if locateRequestID != context.coordinator.lastLocateRequestID {
            context.coordinator.lastLocateRequestID = locateRequestID
            context.coordinator.centerOnUser(in: mapView)
        }

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

    final class Coordinator: NSObject, MKMapViewDelegate, CLLocationManagerDelegate {
        var parent: CafeMapView
        weak var mapView: MKMapView?
        var annotationsByID: [String: CafePointAnnotation] = [:]
        var isProgrammaticRegionChange = false
        var lastLocateRequestID: Int = -1

        private let locationManager = CLLocationManager()
        private var lastLocationRequestAt: Date?

        init(parent: CafeMapView) {
            self.parent = parent
            super.init()
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        }

        func applyAnnotations(to mapView: MKMapView, cafes: [SunnyCafe]) {
            let incomingIDs = Set(cafes.map(\.id))
            var toRemove: [CafePointAnnotation] = []

            for (id, existing) in annotationsByID where !incomingIDs.contains(id) {
                toRemove.append(existing)
                annotationsByID.removeValue(forKey: id)
            }
            if !toRemove.isEmpty {
                mapView.removeAnnotations(toRemove)
            }

            var toAdd: [CafePointAnnotation] = []
            for cafe in cafes {
                if let existing = annotationsByID[cafe.id] {
                    existing.update(with: cafe)
                    if let view = mapView.view(for: existing) as? CafeAnnotationView {
                        view.apply(cafe: cafe)
                    }
                } else {
                    let annotation = CafePointAnnotation(cafe: cafe)
                    annotationsByID[cafe.id] = annotation
                    toAdd.append(annotation)
                }
            }

            if !toAdd.isEmpty {
                mapView.addAnnotations(toAdd)
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
                return nil
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
            view.apply(cafe: cafeAnnotation.cafe)
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
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            DispatchQueue.main.async {
                self.parent.selectedCafe = cafeAnnotation.cafe
                self.parent.onSelectCafe(cafeAnnotation.cafe)
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
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
    }
}

final class CafePointAnnotation: NSObject, MKAnnotation {
    let id: String
    private(set) var cafe: SunnyCafe
    dynamic var coordinate: CLLocationCoordinate2D

    init(cafe: SunnyCafe) {
        self.id = cafe.id
        self.cafe = cafe
        self.coordinate = cafe.coordinate
        super.init()
    }

    func update(with cafe: SunnyCafe) {
        self.cafe = cafe
        self.coordinate = cafe.coordinate
    }

    var title: String? { cafe.name }
}

final class CafeAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "CafeAnnotationView"

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        clusteringIdentifier = "sunny-cafe"
        collisionMode = .circle
        displayPriority = .defaultHigh
        canShowCallout = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isSelected: Bool {
        didSet {
            layer.borderWidth = isSelected ? 2.0 : 0.0
            layer.borderColor = UIColor.white.cgColor
            alpha = isSelected ? 0.95 : 0.88
        }
    }

    func apply(cafe: SunnyCafe) {
        let radius: CGFloat
        if cafe.bucket == .sunny {
            radius = 14
        } else if cafe.bucket == .shaded {
            radius = 10
        } else {
            radius = 12
        }

        frame = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
        layer.cornerRadius = radius
        layer.backgroundColor = UIColor.markerColor(for: cafe.sunnyFraction).cgColor
        alpha = isSelected ? 0.95 : 0.88
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.15
        layer.shadowRadius = 2
        layer.shadowOffset = CGSize(width: 0, height: 1)

        isAccessibilityElement = true
        accessibilityLabel = "\(cafe.name), \(cafe.sunnyPercent) percent sunny, score \(Int(cafe.sunnyScore))"
        accessibilityHint = "Double tap for cafe details."
    }
}

final class CafeClusterAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "CafeClusterAnnotationView"

    private let label = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 34, height: 34)
        layer.cornerRadius = 17
        layer.backgroundColor = UIColor.systemGray3.withAlphaComponent(0.92).cgColor
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.75).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 2

        label.frame = bounds
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .label
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
