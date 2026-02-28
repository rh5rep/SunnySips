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
    let mapDensity: MapDensity
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
        context.coordinator.lastRenderedCafeSignature = context.coordinator.cafeSignature(cafes)
        context.coordinator.lastScheduledRegion = region
        context.coordinator.updateCloudOverlay(on: mapView)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self
        let renderRegion = mapView.region.approximatelyEquals(region) ? mapView.region : region
        let cafeSignature = context.coordinator.cafeSignature(cafes)
        let cafesChanged = cafeSignature != context.coordinator.lastRenderedCafeSignature
        let densityChanged = context.coordinator.lastRenderedMapDensity != mapDensity
        let mapStyleChanged = context.coordinator.lastRenderedUse3DMap != use3DMap
        let regionChanged = context.coordinator.shouldRefreshAnnotations(
            from: context.coordinator.lastScheduledRegion,
            to: renderRegion
        )
        if cafesChanged || densityChanged || mapStyleChanged || regionChanged {
            context.coordinator.scheduleAnnotationRefresh(
                on: mapView,
                cafes: cafes,
                around: renderRegion,
                debounce: (cafesChanged || densityChanged || mapStyleChanged) ? 0.0 : 0.12
            )
        }

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
        var lastRenderedCafeSignature: Int?
        var lastScheduledRegion: MKCoordinateRegion?
        var lastRenderedMapDensity: MapDensity?
        var lastRenderedUse3DMap: Bool?
        private var annotationRefreshTask: DispatchWorkItem?

        private let locationManager = CLLocationManager()
        private var lastLocationRequestAt: Date?

        init(parent: CafeMapView) {
            self.parent = parent
            super.init()
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        }

        func applyAnnotations(to mapView: MKMapView, cafes: [SunnyCafe], around region: MKCoordinateRegion) {
            let selectedCafeID = parent.selectedCafe?.id
            let visibleCafes = cafesNear(region: region, within: cafes, selectedCafeID: selectedCafeID)
            let incomingIDs = Set(visibleCafes.map(\.id))
            let userCoordinate = mapView.userLocation.location?.coordinate
            let isDimmed = parent.warningMessage != nil || parent.isNightMode || parent.sunsetTransitionProgress > 0
            var toRemove: [CafePointAnnotation] = []

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
                    if existing.cafe != cafe || existing.condition != condition {
                        existing.update(with: cafe, condition: condition, distanceMeters: distance)
                        if let view = mapView.view(for: existing) as? CafeAnnotationView {
                            view.apply(cafe: cafe, condition: condition, isDimmed: isDimmed)
                        }
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
            lastRenderedMapDensity = parent.mapDensity
            lastRenderedUse3DMap = parent.use3DMap
        }

        func scheduleAnnotationRefresh(
            on mapView: MKMapView,
            cafes: [SunnyCafe],
            around region: MKCoordinateRegion,
            debounce delay: TimeInterval
        ) {
            annotationRefreshTask?.cancel()
            lastScheduledRegion = region

            let task = DispatchWorkItem { [weak self, weak mapView] in
                guard let self, let mapView else { return }
                self.applyAnnotations(to: mapView, cafes: cafes, around: region)
                self.lastRenderedCafeSignature = self.cafeSignature(cafes)
                self.lastRenderedMapDensity = self.parent.mapDensity
                self.lastRenderedUse3DMap = self.parent.use3DMap
            }
            annotationRefreshTask = task

            if delay <= 0 {
                DispatchQueue.main.async(execute: task)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
            }
        }

        func cafeSignature(_ cafes: [SunnyCafe]) -> Int {
            var hasher = Hasher()
            hasher.combine(cafes.count)
            for cafe in cafes {
                hasher.combine(cafe.id)
                hasher.combine(Int((cafe.sunnyScore * 10.0).rounded()))
                hasher.combine(Int(((cafe.cloudCoverPct ?? -1) * 10.0).rounded()))
            }
            return hasher.finalize()
        }

        private func cafesNear(region: MKCoordinateRegion, within cafes: [SunnyCafe], selectedCafeID: String?) -> [SunnyCafe] {
            let nearby = cafesAround(region: region, within: cafes, bufferScale: annotationBufferScale(for: region))
            let budget = annotationRenderBudget(for: region)
            guard nearby.count > budget else { return nearby }

            var limited = distributedSelection(
                from: nearby,
                budget: budget,
                in: region,
                persistedIDs: Set(annotationsByID.keys)
            )
            if let selectedCafeID,
               !limited.contains(where: { $0.id == selectedCafeID }),
               let selected = nearby.first(where: { $0.id == selectedCafeID }) {
                if limited.isEmpty {
                    limited = [selected]
                } else {
                    limited[limited.count - 1] = selected
                }
            }
            return limited
        }

        private func distributedSelection(
            from cafes: [SunnyCafe],
            budget: Int,
            in region: MKCoordinateRegion,
            persistedIDs: Set<String>
        ) -> [SunnyCafe] {
            guard budget > 0, !cafes.isEmpty else { return [] }

            let aspect = max(0.7, min(1.8, region.span.longitudeDelta / max(region.span.latitudeDelta, 0.0001)))
            let approxRows = max(3, Int((sqrt(Double(max(budget, 1)) / aspect)).rounded()))
            let rows = min(12, approxRows)
            let cols = min(16, max(3, Int((Double(rows) * aspect).rounded())))

            let latMin = region.center.latitude - (region.span.latitudeDelta * 0.5) - max(region.span.latitudeDelta * 0.8, 0.01)
            let latMax = region.center.latitude + (region.span.latitudeDelta * 0.5) + max(region.span.latitudeDelta * 0.8, 0.01)
            let lonMin = region.center.longitude - (region.span.longitudeDelta * 0.5) - max(region.span.longitudeDelta * 0.8, 0.01)
            let lonMax = region.center.longitude + (region.span.longitudeDelta * 0.5) + max(region.span.longitudeDelta * 0.8, 0.01)
            let latRange = max(0.0001, latMax - latMin)
            let lonRange = max(0.0001, lonMax - lonMin)

            var buckets: [Int: [SunnyCafe]] = [:]
            for cafe in cafes {
                let latNorm = max(0.0, min(0.9999, (cafe.lat - latMin) / latRange))
                let lonNorm = max(0.0, min(0.9999, (cafe.lon - lonMin) / lonRange))
                let row = max(0, min(rows - 1, Int(latNorm * Double(rows))))
                let col = max(0, min(cols - 1, Int(lonNorm * Double(cols))))
                let key = (row * cols) + col
                buckets[key, default: []].append(cafe)
            }

            let orderedKeys = buckets.keys.sorted()
            for key in orderedKeys {
                buckets[key]?.sort { lhs, rhs in
                    bucketSort(lhs, rhs, persistedIDs: persistedIDs)
                }
            }

            var result: [SunnyCafe] = []
            var nextIndexByKey: [Int: Int] = [:]

            for key in orderedKeys {
                guard let bucket = buckets[key], !bucket.isEmpty else { continue }
                result.append(bucket[0])
                nextIndexByKey[key] = 1
                if result.count == budget {
                    return result
                }
            }

            var advanced = true
            while result.count < budget && advanced {
                advanced = false
                for key in orderedKeys {
                    guard let bucket = buckets[key] else { continue }
                    let index = nextIndexByKey[key] ?? 0
                    guard index < bucket.count else { continue }
                    result.append(bucket[index])
                    nextIndexByKey[key] = index + 1
                    advanced = true
                    if result.count == budget {
                        break
                    }
                }
            }

            return result
        }

        private func cafesAround(region: MKCoordinateRegion, within cafes: [SunnyCafe], bufferScale: Double) -> [SunnyCafe] {
            // Keep a small buffer around the viewport so panning feels smooth without rendering the full dataset.
            let latitudeBuffer = max(region.span.latitudeDelta * bufferScale, 0.01)
            let longitudeBuffer = max(region.span.longitudeDelta * bufferScale, 0.01)

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

        func shouldRefreshAnnotations(from previous: MKCoordinateRegion?, to next: MKCoordinateRegion) -> Bool {
            guard let previous else { return true }

            let latitudeShift = abs(next.center.latitude - previous.center.latitude)
            let longitudeShift = abs(next.center.longitude - previous.center.longitude)
            let latitudeThreshold = max(previous.span.latitudeDelta * 0.18, 0.0018)
            let longitudeThreshold = max(previous.span.longitudeDelta * 0.18, 0.0018)

            let previousZoom = max(previous.span.latitudeDelta, previous.span.longitudeDelta)
            let nextZoom = max(next.span.latitudeDelta, next.span.longitudeDelta)
            let zoomRatio = max(
                nextZoom / max(previousZoom, 0.0001),
                previousZoom / max(nextZoom, 0.0001)
            )

            return latitudeShift > latitudeThreshold ||
                longitudeShift > longitudeThreshold ||
                zoomRatio > 1.12
        }

        private func annotationRenderBudget(for region: MKCoordinateRegion) -> Int {
            let zoomMetric = max(region.span.latitudeDelta, region.span.longitudeDelta)
            let baseBudget: Int
            if zoomMetric > 0.11 {
                baseBudget = 220
            } else if zoomMetric > 0.07 {
                baseBudget = 280
            } else if zoomMetric > 0.035 {
                baseBudget = 360
            } else {
                baseBudget = 430
            }
            let densityAdjusted = max(60, Int(Double(baseBudget) * parent.mapDensity.annotationBudgetMultiplier))
            if parent.use3DMap {
                return max(45, Int(Double(densityAdjusted) * 0.72))
            }
            return densityAdjusted
        }

        private func annotationBufferScale(for region: MKCoordinateRegion) -> Double {
            let zoomMetric = max(region.span.latitudeDelta, region.span.longitudeDelta)
            let baseScale: Double
            if zoomMetric > 0.11 {
                baseScale = 1.45
            } else if zoomMetric > 0.07 {
                baseScale = 1.25
            } else if zoomMetric > 0.035 {
                baseScale = 1.05
            } else {
                baseScale = 0.82
            }
            switch parent.mapDensity {
            case .focused:
                return max(0.72, baseScale - 0.12)
            case .balanced:
                return baseScale
            case .dense:
                return baseScale + 0.18
            }
        }

        private func bucketSort(_ lhs: SunnyCafe, _ rhs: SunnyCafe, persistedIDs: Set<String>) -> Bool {
            let leftPersisted = persistedIDs.contains(lhs.id)
            let rightPersisted = persistedIDs.contains(rhs.id)
            if leftPersisted != rightPersisted {
                return leftPersisted
            }
            if lhs.sunnyScore != rhs.sunnyScore {
                return lhs.sunnyScore > rhs.sunnyScore
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
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
                let rect = cluster.memberAnnotations.reduce(MKMapRect.null) { partial, annotation in
                    partial.union(
                        MKMapRect(
                            origin: MKMapPoint(annotation.coordinate),
                            size: MKMapSize(width: 0, height: 0)
                        )
                    )
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
            if shouldRefreshAnnotations(from: lastScheduledRegion, to: mapView.region) {
                scheduleAnnotationRefresh(
                    on: mapView,
                    cafes: parent.cafes,
                    around: mapView.region,
                    debounce: 0.08
                )
            }

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
        bubbleView.layer.shadowOpacity = isSelected ? 0.24 : 0.16
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
    private static let size: CGFloat = 34

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: Self.size, height: Self.size)
        bounds = frame
        layer.cornerRadius = Self.size / 2.0
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowOpacity = 0.2
        layer.shadowRadius = 3
        backgroundColor = UIColor(red: 0.16, green: 0.13, blue: 0.11, alpha: 0.76)
        layer.borderWidth = 1.2
        layer.borderColor = UIColor.white.withAlphaComponent(0.7).cgColor

        label.frame = bounds
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 13, weight: .bold)
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
        alpha = 0.92
        accessibilityLabel = "\(count) cafes clustered"
    }
}
