library google_places_flutter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_places_flutter/model/place_details.dart';
import 'package:google_places_flutter/model/place_type.dart';
import 'package:google_places_flutter/model/prediction.dart';

import 'package:dio/dio.dart';
import 'package:rxdart/rxdart.dart';

import 'DioErrorHandler.dart';

typedef LatLngInputDetected = void Function(String latLngString);

class GooglePlaceAutoCompleteTextField extends StatefulWidget {
  InputDecoration inputDecoration;
  ItemClick? itemClick;
  GetPlaceDetailswWithLatLng? getPlaceDetailWithLatLng;
  bool isLatLngRequired = true;

  TextStyle textStyle;
  String googleAPIKey;
  int debounceTime = 600;
  List<String>? countries = [];
  TextEditingController textEditingController = TextEditingController();
  ListItemBuilder? itemBuilder;
  Widget? seperatedBuilder;
  BoxDecoration? boxDecoration;
  bool isCrossBtnShown;
  bool showError;
  double? containerHorizontalPadding;
  double? containerVerticalPadding;
  FocusNode? focusNode;
  PlaceType? placeType;
  String? language;
  TextInputAction? textInputAction;
  final VoidCallback? formSubmitCallback;

  final String? Function(String?, BuildContext)? validator;

  final double? latitude;
  final double? longitude;

  /// This is expressed in **meters**
  final int? radius;

  /// Callback function to be invoked when the input text resembles a LatLng coordinate pair.
  /// The API call will be skipped when this callback is triggered.
  final LatLngInputDetected? onLatLngInputDetected;

  GooglePlaceAutoCompleteTextField(
      {required this.textEditingController,
      required this.googleAPIKey,
      this.debounceTime = 600,
      this.inputDecoration = const InputDecoration(),
      this.itemClick,
      this.isLatLngRequired = true,
      this.textStyle = const TextStyle(),
      this.countries,
      this.getPlaceDetailWithLatLng,
      this.itemBuilder,
      this.boxDecoration,
      this.isCrossBtnShown = true,
      this.seperatedBuilder,
      this.showError = true,
      this.containerHorizontalPadding,
      this.containerVerticalPadding,
      this.focusNode,
      this.placeType,
      this.language = 'en',
      this.validator,
      this.latitude,
      this.longitude,
      this.radius,
      this.formSubmitCallback,
      this.textInputAction,
      this.onLatLngInputDetected});

  @override
  _GooglePlaceAutoCompleteTextFieldState createState() =>
      _GooglePlaceAutoCompleteTextFieldState();
}

class _GooglePlaceAutoCompleteTextFieldState
    extends State<GooglePlaceAutoCompleteTextField> {
  final subject = new PublishSubject<String>();
  OverlayEntry? _overlayEntry;
  List<Prediction> alPredictions = [];

  TextEditingController controller = TextEditingController();
  final LayerLink _layerLink = LayerLink();
  bool isSearched = false;

  bool isCrossBtn = true;
  late var _dio;

  CancelToken? _cancelToken = CancelToken();

  /// Regex to detect "lat, lng" pattern with space and decimals
  /// ("12.34,56.78", "12.34, 56.78", "-12, 56", etc)
  final _latLngRegex = RegExp(r'^-?\d+(\.\d+)?\s*,\s*-?\d+(\.\d+)?$');

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: widget.containerHorizontalPadding ?? 0,
            vertical: widget.containerVerticalPadding ?? 0),
        alignment: Alignment.centerLeft,
        decoration: widget.boxDecoration ??
            BoxDecoration(
                shape: BoxShape.rectangle,
                border: Border.all(color: Colors.grey, width: 0.6),
                borderRadius: BorderRadius.all(Radius.circular(10))),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextFormField(
                decoration: widget.inputDecoration,
                style: widget.textStyle,
                controller: widget.textEditingController,
                focusNode: widget.focusNode ?? FocusNode(),
                textInputAction: widget.textInputAction ?? TextInputAction.done,
                onFieldSubmitted: (value) {
                  if (widget.formSubmitCallback != null) {
                    widget.formSubmitCallback!();
                  }

                  // Remove overlay on submit
                  _removeOverlay();
                },
                validator: (inputString) {
                  return widget.validator?.call(inputString, context);
                },
                onChanged: (string) {
                  subject.add(string);
                  if (widget.isCrossBtnShown) {
                    isCrossBtn = string.isNotEmpty ? true : false;
                    setState(() {});
                  }
                },
              ),
            ),
            (!widget.isCrossBtnShown || !isCrossBtn)
                ? SizedBox()
                : IconButton(onPressed: clearData, icon: Icon(Icons.close))
          ],
        ),
      ),
    );
  }

  getLocation(String text) async {
    String apiURL =
        "https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$text&key=${widget.googleAPIKey}&language=${widget.language}";

    if (widget.countries != null) {
      // in

      for (int i = 0; i < widget.countries!.length; i++) {
        String country = widget.countries![i];

        if (i == 0) {
          apiURL = apiURL + "&components=country:$country";
        } else {
          apiURL = apiURL + "|" + "country:" + country;
        }
      }
    }
    if (widget.placeType != null) {
      apiURL += "&types=${widget.placeType?.apiString}";
    }

    if (widget.latitude != null &&
        widget.longitude != null &&
        widget.radius != null) {
      apiURL = apiURL +
          "&location=${widget.latitude},${widget.longitude}&radius=${widget.radius}";
    }

    if (_cancelToken?.isCancelled == false) {
      _cancelToken?.cancel();
      _cancelToken = CancelToken();
    }

    // print("urlll $apiURL");
    try {
      String proxyURL = "https://cors-anywhere.herokuapp.com/";
      String url = kIsWeb ? proxyURL + apiURL : apiURL;

      // Ensure previous overlay is removed before showing new results
      _removeOverlay();

      Response response = await _dio.get(url, cancelToken: _cancelToken);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      Map map = response.data;
      if (map.containsKey("error_message")) {
        throw response.data;
      }

      PlacesAutocompleteResponse subscriptionResponse =
          PlacesAutocompleteResponse.fromJson(response.data);

      // Redundant check? text.length == 0 is handled in textChanged
      // if (text.length == 0) {
      //   alPredictions.clear();
      //   _removeOverlay(); // Ensure overlay is removed
      //   return;
      // }

      isSearched = false; // What is this used for? Seems unused
      alPredictions.clear();
      if (subscriptionResponse.predictions!.length > 0 &&
          (widget.textEditingController.text.toString().trim()).isNotEmpty) {
        alPredictions.addAll(subscriptionResponse.predictions!);
      }

      // Only show overlay if there are predictions
      if (alPredictions.isNotEmpty) {
        this._overlayEntry = this._createOverlayEntry();
        if (this._overlayEntry != null) {
          Overlay.of(context).insert(this._overlayEntry!);
        }
      } else {
        // If no predictions, ensure overlay is removed
        _removeOverlay();
      }
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        // Request was cancelled (e.g., user typed quickly), ignore error.
        print("Request cancelled");
      } else {
        // Handle other errors
        var errorHandler = ErrorHandler.internal().handleError(e);
        _showSnackBar("${errorHandler.message}");
        // Clear predictions and overlay on error
        setState(() {
          alPredictions.clear();
        });
        _removeOverlay();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _dio = Dio();
    subject.stream
        .distinct()
        .debounceTime(Duration(milliseconds: widget.debounceTime))
        .listen(textChanged);

    // Ensure cross button visibility is correct initially
    isCrossBtn = widget.textEditingController.text.isNotEmpty;
  }

  @override
  void dispose() {
    subject.close(); // Close the stream controller
    _cancelToken?.cancel(); // Cancel any ongoing requests
    _dio.close(force: true); // Close the dio instance
    _removeOverlay(); // Ensure overlay is removed on dispose
    // Don't dispose the controller passed from the parent widget
    // widget.textEditingController.dispose();
    // Don't dispose the focus node passed from the parent widget
    // widget.focusNode?.dispose();
    super.dispose();
  }

  textChanged(String text) async {
    String trimmedText = text.trim();

    // If text is empty, clear predictions and remove overlay
    if (trimmedText.isEmpty) {
      setState(() {
        alPredictions.clear();
        // Update cross button state if needed (already handled by onChanged)
      });
      _removeOverlay();
      return; // Stop processing
    }

    // Check if the input matches the LatLng pattern
    if (_latLngRegex.hasMatch(trimmedText)) {
      // If it matches, call the callback and do *not* proceed to API call
      widget.onLatLngInputDetected?.call(trimmedText);
      // Clear any existing predictions and remove the overlay
      setState(() {
        alPredictions.clear();
      });
      _removeOverlay();
      return; // Stop processing, skip API call
    }

    // If text is not empty and not a LatLng pattern, proceed with API call
    getLocation(trimmedText);
  }

  OverlayEntry? _createOverlayEntry() {
    // Ensure the context is still valid and mounted before creating overlay
    if (!mounted || context.findRenderObject() == null) return null;

    RenderBox renderBox = context.findRenderObject() as RenderBox;
    var size = renderBox.size;
    var offset = renderBox.localToGlobal(Offset.zero);

    // Ensure overlay doesn't go off-screen vertically
    final screenHeight = MediaQuery.of(context).size.height;
    final maxOverlayHeight =
        screenHeight - (offset.dy + size.height + 10); // Add some padding

    return OverlayEntry(
        builder: (context) => Positioned(
            left: offset.dx,
            top: size.height + offset.dy,
            width: size.width,
            child: CompositedTransformFollower(
              showWhenUnlinked: false,
              link: this._layerLink,
              offset: Offset(0.0, size.height + 5.0),
              child: Material(
                elevation: 4.0, // Add elevation for visual separation
                child: ConstrainedBox(
                    // Limit overlay height
                    constraints: BoxConstraints(
                        maxHeight: maxOverlayHeight > 100
                            ? maxOverlayHeight
                            : 100 // Min height
                        ),
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: alPredictions.length,
                      separatorBuilder: (context, pos) =>
                          widget.seperatedBuilder ?? const Divider(height: 1),
                      itemBuilder: (BuildContext context, int index) {
                        return InkWell(
                          onTap: () async {
                            var selectedData = alPredictions[index];
                            // Check index validity just in case
                            if (index < alPredictions.length) {
                              // Hide keyboard
                              FocusScope.of(context).unfocus();

                              // Update text field before potentially slow details fetch
                              widget.textEditingController.text =
                                  selectedData.description ?? '';

                              // Move cursor to end
                              widget.textEditingController.selection =
                                  TextSelection.fromPosition(
                                TextPosition(
                                    offset: widget
                                        .textEditingController.text.length),
                              );

                              // Call itemClick callback immediately
                              widget.itemClick?.call(selectedData);

                              // Clear predictions and remove overlay *before* async call
                              setState(() {
                                alPredictions.clear();
                              });
                              _removeOverlay();

                              // Fetch details if required (can take time)
                              if (widget.isLatLngRequired) {
                                await getPlaceDetailsFromPlaceId(selectedData);
                              }
                            }
                          },
                          child: widget.itemBuilder != null
                              ? widget.itemBuilder!(
                                  context, index, alPredictions[index])
                              : Container(
                                  padding: EdgeInsets.all(10),
                                  child:
                                      Text(alPredictions[index].description!)),
                        );
                      },
                    )),
              ),
            )));
  }

  // Renamed from removeOverlay to avoid confusion with OverlayEntry.remove()
  /// Clears predictions and removes the overlay entry.
  void _removeOverlay() {
    // Check if overlay exists and is part of the overlay tree
    if (this._overlayEntry != null) {
      try {
        this._overlayEntry?.remove();
      } catch (e) {
        print("Error removing overlay: $e");
      }
      _overlayEntry = null; // Ensure reference is cleared
    }

    // Also clear the predictions list associated with the overlay
    // This might be redundant if called from places that already clear it, but safe.
    // setState(() {
    //   alPredictions.clear();
    // });
  }

  Future<void> getPlaceDetailsFromPlaceId(Prediction prediction) async {
    //String key = GlobalConfiguration().getString('google_maps_key');

    var url =
        "https://maps.googleapis.com/maps/api/place/details/json?placeid=${prediction.placeId}&key=${widget.googleAPIKey}";
    try {
      Response response = await _dio.get(
        url,
      );

      PlaceDetails placeDetails = PlaceDetails.fromJson(response.data);

      prediction.lat = placeDetails.result?.geometry?.location?.lat.toString();
      prediction.lng = placeDetails.result?.geometry?.location?.lng.toString();

      // Check if lat/lng were successfully retrieved
      if (prediction.lat != null && prediction.lng != null) {
        // print(222222); // Keep for debugging if needed
        widget.getPlaceDetailWithLatLng?.call(prediction);
      } else {
        _showSnackBar("Could not retrieve coordinates for the selected place.");
      }
    } catch (e) {
      var errorHandler = ErrorHandler.internal().handleError(e);
      _showSnackBar("${errorHandler.message}");
    }
  }

  void clearData() {
    widget.textEditingController.clear();
    if (_cancelToken?.isCancelled == false) {
      _cancelToken?.cancel();
    }

    setState(() {
      alPredictions.clear();
      isCrossBtn = false;
    });

    _removeOverlay(); // Use the helper method to remove overlay
  }

  _showSnackBar(String errorData) {
    if (widget.showError && mounted) {
      // Check if widget is still mounted
      final snackBar = SnackBar(
        content: Text(errorData), // Removed unnecessary interpolation
      );

      // Find the ScaffoldMessenger in the widget tree
      // and use it to show a SnackBar.
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    }
  }
}

PlacesAutocompleteResponse parseResponse(Map responseBody) {
  return PlacesAutocompleteResponse.fromJson(
      responseBody as Map<String, dynamic>);
}

PlaceDetails parsePlaceDetailMap(Map responseBody) {
  return PlaceDetails.fromJson(responseBody as Map<String, dynamic>);
}

typedef ItemClick = void Function(Prediction postalCodeResponse);
typedef GetPlaceDetailswWithLatLng = void Function(
    Prediction postalCodeResponse);

typedef ListItemBuilder = Widget Function(
    BuildContext context, int index, Prediction prediction);
