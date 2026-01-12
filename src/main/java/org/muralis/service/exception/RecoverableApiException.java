package org.muralis.service.exception;

public class RecoverableApiException extends ApiException {
    
    public RecoverableApiException(String message) {
        super(message);
    }
    
    public RecoverableApiException(String message, Throwable cause) {
        super(message, cause);
    }
}
